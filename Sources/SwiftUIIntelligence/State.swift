import Foundation
import Observation

public struct TimelineEvent: Codable, Sendable {
  public let cardColor: CardColor?
  public let timeBinding: String?
  public let detailBinding: String?
  public let time: String
  public let title: String
  public let detail: String
  public init(from decoder: any Decoder) throws {
    try checkKeys(decoder, allowed: ["time", "title", "detail", "cardColor", "timeBinding", "detailBinding"])
    let c = try decoder.container(keyedBy: CodingKeys.self)
    timeBinding = c.contains(.timeBinding) ? try c.decode(String.self, forKey: .timeBinding) : nil
    detailBinding = c.contains(.detailBinding) ? try c.decode(String.self, forKey: .detailBinding) : nil
    cardColor = c.contains(.cardColor) ? try c.decode(CardColor.self, forKey: .cardColor) : nil
    time = try c.decode(String.self, forKey: .time)
    title = try c.decode(String.self, forKey: .title)
    detail = try c.decode(String.self, forKey: .detail)
  }
  init(time: String, title: String, detail: String) {
    self.time = time
    self.title = title
    self.detail = detail
    self.timeBinding = nil
    self.detailBinding = nil
    self.cardColor = nil
  }

  public func resolvedTime(in values: [String: StateValue]) throws -> String {
    try resolve(timeBinding, fallback: time, values: values, maximum: 80, nonempty: true)
  }
  public func resolvedDetail(in values: [String: StateValue]) throws -> String {
    try resolve(detailBinding, fallback: detail, values: values, maximum: 1000, nonempty: false)
  }
  private func resolve(_ binding: String?, fallback: String, values: [String: StateValue], maximum: Int, nonempty: Bool) throws -> String {
    guard let binding else { return fallback }
    guard case .text(let text) = values[binding], text.count <= maximum,
      !nonempty || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw UIError("Timeline binding requires bounded text.")
    }
    return text
  }
  private enum CodingKeys: String, CodingKey { case time, title, detail, cardColor, timeBinding, detailBinding }
}

/// JSON primitives have explicit Swift types. No expression evaluation or coercion.
public enum StateValue: Codable, Equatable, Sendable {
  case text(String), number(Double), boolean(Bool)
  public init(from decoder: any Decoder) throws {
    let c = try decoder.singleValueContainer()
    if let b = try? c.decode(Bool.self) { self = .boolean(b) }
    else if let n = try? c.decode(Double.self) { self = .number(n) }
    else { self = .text(try c.decode(String.self)) }
  }
  public func encode(to encoder: any Encoder) throws {
    var c = encoder.singleValueContainer()
    switch self {
    case .text(let v): try c.encode(v)
    case .number(let v): try c.encode(v)
    case .boolean(let v): try c.encode(v)
    }
  }
}

public struct StateField: Codable, Sendable {
  public enum Kind: String, Codable, Sendable, CaseIterable { case text, number, boolean, choice, date }
  public let id: String
  public let kind: Kind
  public let value: StateValue
  public let options: [String]
  public let minimum: Double
  public let maximum: Double
  public let step: Double
  private enum CodingKeys: String, CodingKey { case id, kind, value, options, minimum, maximum, step }
  public init(from decoder: any Decoder) throws {
    try checkKeys(decoder, allowed: ["id", "kind", "value", "options", "minimum", "maximum", "step"])
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decode(String.self, forKey: .id); kind = try c.decode(Kind.self, forKey: .kind)
    value = try c.decode(StateValue.self, forKey: .value)
    options = try c.decodeIfPresent([String].self, forKey: .options) ?? []
    minimum = try c.decodeIfPresent(Double.self, forKey: .minimum) ?? 0
    maximum = try c.decodeIfPresent(Double.self, forKey: .maximum) ?? 100
    step = try c.decodeIfPresent(Double.self, forKey: .step) ?? 1
  }
  public func encode(to encoder: any Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(id, forKey: .id); try c.encode(kind, forKey: .kind); try c.encode(value, forKey: .value)
    if kind == .choice { try c.encode(options, forKey: .options) }
    if kind == .number {
      try c.encode(minimum, forKey: .minimum); try c.encode(maximum, forKey: .maximum); try c.encode(step, forKey: .step)
    }
  }
  public func validate(_ candidate: StateValue) throws {
    switch (kind, candidate) {
    case (.boolean, .boolean): break
    case (.text, .text(let v)): guard v.count <= 4000 else { throw UIError("State text is too long.") }
    case (.choice, .text(let v)): guard options.contains(v) else { throw UIError("Choice must be a declared option.") }
    case (.date, .text(let v)): guard ISO8601DateFormatter().date(from: v) != nil else { throw UIError("Date must be an ISO8601 instant.") }
    case (.number, .number(let v)):
      guard v.isFinite, (minimum...maximum).contains(v) else { throw UIError("Numeric state is outside its bounds.") }
    default: throw UIError("State value does not match its declared type.")
    }
  }
}

extension UIDocument {
  func validateState() throws {
    guard state.count <= 32, Set(state.map(\.id)).count == state.count else { throw UIError("State requires at most 32 unique fields.") }
    for field in state {
      guard validIdentifier(field.id), field.minimum.isFinite, field.maximum.isFinite,
        abs(field.minimum) <= 1e9, abs(field.maximum) <= 1e9, field.minimum <= field.maximum,
        field.step.isFinite, field.step > 0, field.step <= 1e9,
        field.options.count <= 32, Set(field.options).count == field.options.count,
        field.options.allSatisfy({ !$0.isEmpty && $0.count <= 80 }),
        field.kind != .choice || !field.options.isEmpty else { throw UIError("Invalid state declaration '\(field.id)'.") }
      try field.validate(field.value)
    }
  }
}

/// Owned by the host; keep the same instance across navigation to preserve edits.
/// User edits are never included in model prompts or diagnostics automatically.
@MainActor @Observable public final class DocumentState {
  public private(set) var values: [String: StateValue] = [:]
  public private(set) var records: [String: [RecordRow]] = [:]
  public private(set) var errorMessage: String?
  private var edited = Set<String>()
  private var fields: [String: StateField] = [:]
  private var calculationPlan: CalculationPlan?
  private var presentationDocument: UIDocument?
  private var recordSchemas: [String: RecordSchema] = [:]
  private struct RecordEdit: Hashable { let collection: String; let row: String; let field: String }
  private var recordEdits = Set<RecordEdit>()
  public init() {}
  public func load(_ document: UIDocument, preservingEdits: Bool = true) {
    guard document.calculations.isEmpty else {
      errorMessage = "This document requires its host calculation registry."
      return
    }
    do {
      try document.validateState()
      try document.validateRecords()
      try document.validateRecordProjectionSchemas(Dictionary(uniqueKeysWithValues: document.records.map { ($0.id, $0.schema) }))
    } catch { errorMessage = error.localizedDescription; return }
    let candidateFields = Dictionary(uniqueKeysWithValues: document.state.map { ($0.id, $0) })
    var retainedEdits = Set<String>()
    let candidate = Dictionary(uniqueKeysWithValues: document.state.map { field in
      if preservingEdits, edited.contains(field.id), let retained = values[field.id], (try? field.validate(retained)) != nil {
        retainedEdits.insert(field.id)
        return (field.id, retained)
      }
      return (field.id, field.value)
    })
    let recordCandidate = retainedRecords(document, preservingEdits: preservingEdits)
    do { try document.validatePresentation(values: candidate, records: recordCandidate.values) }
    catch { errorMessage = error.localizedDescription; return }
    fields = candidateFields
    values = candidate
    records = recordCandidate.values
    recordSchemas = Dictionary(uniqueKeysWithValues: document.records.map { ($0.id, $0.schema) })
    recordEdits = recordCandidate.edits
    calculationPlan = nil
    presentationDocument = document
    edited = retainedEdits
    errorMessage = nil
  }
  public func load(_ document: UIDocument, calculations: CalculationRegistry, preservingEdits: Bool = true) throws {
    try load(document, calculations: calculations, bindings: document.calculations, preservingEdits: preservingEdits)
  }

  public func load(_ document: UIDocument, calculations: CalculationRegistry,
    bindings: [CalculationBinding], preservingEdits: Bool = true) throws {
    try document.validateState()
    try document.validateRecords()
    let candidateFields = Dictionary(uniqueKeysWithValues: document.state.map { ($0.id, $0) })
    let schemas = Dictionary(uniqueKeysWithValues: document.records.map { ($0.id, $0.schema) })
    let plan = try CalculationPlan(registry: calculations, bindings: bindings, fields: candidateFields, recordSchemas: schemas)
    try document.validateRecordFields(bindings: bindings, registry: calculations)
    var candidate = Dictionary(uniqueKeysWithValues: document.state.map { ($0.id, $0.value) })
    var retained = Set<String>()
    for field in document.state where preservingEdits && edited.contains(field.id) && !plan.derivedFields.contains(field.id) {
      if let value = values[field.id], (try? field.validate(value)) != nil {
        candidate[field.id] = value
        retained.insert(field.id)
      }
    }
    let recordCandidate = retainedRecords(document, preservingEdits: preservingEdits)
    let evaluated = try plan.evaluate(candidate, fields: candidateFields, inputRecords: recordCandidate.values)
    try document.validatePresentation(values: evaluated.values, records: evaluated.records)
    recordSchemas = schemas
    recordEdits = recordCandidate.edits
    fields = candidateFields
    values = evaluated.values
    records = evaluated.records
    edited = retained
    calculationPlan = plan
    presentationDocument = document
    errorMessage = nil
  }

  public func set(_ id: String, to value: StateValue) throws {
    guard let field = fields[id] else { throw UIError("Unknown state binding '\(id)'.") }
    guard calculationPlan?.derivedFields.contains(id) != true else { throw UIError("Derived state is read-only.") }
    try field.validate(value)
    var candidate = values
    candidate[id] = value
    var candidateRecords = records
    if let calculationPlan {
      let inputs = records.filter { recordSchemas[$0.key] != nil }
      let result = try calculationPlan.evaluate(candidate, fields: fields, inputRecords: inputs)
      candidate = result.values
      candidateRecords = result.records
    }
    try presentationDocument?.validatePresentation(values: candidate, records: candidateRecords)
    values = candidate
    records = candidateRecords
    edited.insert(id)
    errorMessage = nil
  }
  private func retainedRecords(_ document: UIDocument, preservingEdits: Bool) -> (values: [String: [RecordRow]], edits: Set<RecordEdit>) {
    var candidate = Dictionary(uniqueKeysWithValues: document.records.map { ($0.id, $0.rows) })
    var retained = Set<RecordEdit>()
    for edit in recordEdits where preservingEdits {
      guard let declaration = document.records.first(where: { $0.id == edit.collection }),
        let index = candidate[edit.collection]?.firstIndex(where: { $0.id == edit.row }),
        let old = records[edit.collection]?.first(where: { $0.id == edit.row })?.values[edit.field] else { continue }
      var values = candidate[edit.collection]![index].values
      values[edit.field] = old
      let row = RecordRow(id: edit.row, values: values)
      if (try? declaration.schema.validate([row])) != nil {
        candidate[edit.collection]![index] = row
        retained.insert(edit)
      }
    }
    return (candidate, retained)
  }

  public func setRecord(_ collection: String, row id: String, field: String, to value: StateValue) throws {
    guard let schema = recordSchemas[collection], var rows = records[collection],
      let index = rows.firstIndex(where: { $0.id == id }), schema.fields[field] != nil else {
      throw UIError("Unknown editable record cell.")
    }
    if rows[index].values[field] == value { return }
    var fields = rows[index].values
    fields[field] = value
    rows[index] = RecordRow(id: id, values: fields)
    try schema.validate(rows)
    var candidate = records
    candidate[collection] = rows
    var candidateValues = values
    if let calculationPlan {
      let inputs = candidate.filter { recordSchemas[$0.key] != nil }
      let result = try calculationPlan.evaluate(values, fields: self.fields, inputRecords: inputs)
      candidateValues = result.values
      candidate = result.records
    }
    try presentationDocument?.validatePresentation(values: candidateValues, records: candidate)
    values = candidateValues
    records = candidate
    recordEdits.insert(.init(collection: collection, row: id, field: field))
    errorMessage = nil
  }

  func editRecord(_ collection: String, row: String, field: String, to value: StateValue) {
    do { try setRecord(collection, row: row, field: field, to: value) }
    catch { errorMessage = error.localizedDescription }
  }

  func edit(_ id: String, _ value: StateValue) {
    do { try set(id, to: value) } catch { errorMessage = error.localizedDescription }
  }
  func field(_ id: String) -> StateField? { fields[id] }
}
