import Foundation
import Observation

public struct TimelineEvent: Codable, Sendable {
  public let time: String
  public let title: String
  public let detail: String
  public init(from decoder: any Decoder) throws {
    try checkKeys(decoder, allowed: ["time", "title", "detail"])
    let c = try decoder.container(keyedBy: CodingKeys.self)
    time = try c.decode(String.self, forKey: .time)
    title = try c.decode(String.self, forKey: .title)
    detail = try c.decode(String.self, forKey: .detail)
  }
  private enum CodingKeys: String, CodingKey { case time, title, detail }
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
  public private(set) var errorMessage: String?
  private var edited = Set<String>()
  private var fields: [String: StateField] = [:]
  public init() {}
  public func load(_ document: UIDocument, preservingEdits: Bool = true) {
    do { try document.validateState() } catch { errorMessage = error.localizedDescription; return }
    fields = Dictionary(uniqueKeysWithValues: document.state.map { ($0.id, $0) })
    var retainedEdits = Set<String>()
    values = Dictionary(uniqueKeysWithValues: document.state.map { field in
      if preservingEdits, edited.contains(field.id), let retained = values[field.id], (try? field.validate(retained)) != nil {
        retainedEdits.insert(field.id)
        return (field.id, retained)
      }
      return (field.id, field.value)
    })
    edited = retainedEdits
    errorMessage = nil
  }
  public func set(_ id: String, to value: StateValue) throws {
    guard let field = fields[id] else { throw UIError("Unknown state binding '\(id)'.") }
    try field.validate(value); values[id] = value; edited.insert(id); errorMessage = nil
  }
  func edit(_ id: String, _ value: StateValue) {
    do { try set(id, to: value) } catch { errorMessage = error.localizedDescription }
  }
  func field(_ id: String) -> StateField? { fields[id] }
}
