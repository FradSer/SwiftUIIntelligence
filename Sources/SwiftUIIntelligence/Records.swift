import Foundation

/// A flat, typed row. Field names are identifiers, not executable property paths.
public struct RecordRow: Codable, Identifiable, Sendable, Equatable {
  public let id: String
  public let values: [String: StateValue]

  public init(id: String, values: [String: StateValue]) {
    self.id = id
    self.values = values
  }

  private enum CodingKeys: String, CodingKey { case id, values }
  public init(from decoder: any Decoder) throws {
    try checkKeys(decoder, allowed: ["id", "values"])
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    values = try container.decode([String: StateValue].self, forKey: .values)
  }
}

extension UIDocument {
  @MainActor func validateRecordFields(bindings: [CalculationBinding], registry: CalculationRegistry) throws {
    var schemas = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0.schema) })
    for binding in bindings {
      let capability = try registry.signature(binding.capability)
      for (parameter, collection) in binding.recordOutputs {
        guard let schema = capability.recordOutputs[parameter] else { throw UIError("Unknown record output parameter.") }
        schemas[collection] = schema
      }
    }
    try validateRecordProjectionSchemas(schemas)
  }

  /// Checks projected field names and kinds using metadata only. No calculation executes.
  public func validateRecordFields(signatures: [CalculationRegistry.Signature]) throws {
    var schemas = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0.schema) })
    for binding in calculations {
      guard let signature = signatures.first(where: { $0.id == binding.capability }) else {
        throw UIError("Missing calculation signature for record projection.")
      }
      for (parameter, collection) in binding.recordOutputs {
        guard let schema = signature.recordOutputs[parameter] else { throw UIError("Unknown record output parameter.") }
        schemas[collection] = schema
      }
    }
    try validateRecordProjectionSchemas(schemas)
  }

  func validateRecordProjectionSchemas(_ schemas: [String: RecordSchema]) throws {
    func visit(_ node: UINode) throws {
      if let source = node.recordSource {
        guard let schema = schemas[source], node.recordFields.allSatisfy({ schema.fields[$0] != nil }) else {
          throw UIError("Presentation references an unknown record field or collection.")
        }
        if node.type == .timeline {
          guard node.recordFields.count == 3, node.recordFields.allSatisfy({ schema.fields[$0] == .text }) else {
            throw UIError("Timeline records require three text fields.")
          }
        }
        if node.type == .chart {
          guard node.recordFields.count == 3,
            schema.fields[node.recordFields[0]] == .text, schema.fields[node.recordFields[1]] == .number,
            schema.fields[node.recordFields[2]] == .text else { throw UIError("Chart records require text, number, and text fields.") }
        }
        if node.type == .list {
          guard node.recordFields.count == 1, let field = node.recordFields.first, schema.fields[field] == .text else {
            throw UIError("List records require one text field.")
          }
        }
      }
      try node.children.forEach(visit)
    }
    try visit(root)
  }
}

extension UINode {
  public func resolvedEvents(in records: [String: [RecordRow]]) throws -> [TimelineEvent] {
    guard let recordSource else { return events }
    guard let rows = records[recordSource], recordFields.count == 3 else { throw UIError("Timeline records are not available.") }
    return try rows.map { row in
      guard case .text(let time) = row.values[recordFields[0]],
        case .text(let title) = row.values[recordFields[1]],
        case .text(let detail) = row.values[recordFields[2]],
        !time.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, time.count <= 80,
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, title.count <= 160, detail.count <= 1000 else {
        throw UIError("Timeline records require bounded time, title, and detail text.")
      }
      return TimelineEvent(time: time, title: title, detail: detail)
    }
  }

  public func resolvedItems(in records: [String: [RecordRow]]) throws -> [String] {
    guard let recordSource else { return items }
    guard let collection = records[recordSource], let field = recordFields.first else {
      throw UIError("List record collection is not available.")
    }
    return try collection.map { row in
      guard case .text(let text) = row.values[field], !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw UIError("List records require nonempty text.")
      }
      return text
    }
  }

  public func resolvedRows(in records: [String: [RecordRow]]) throws -> [[String]] {
    guard let recordSource else { return rows }
    guard let collection = records[recordSource] else { throw UIError("Table record collection is not available.") }
    return try collection.map { row in
      try recordFields.map { field in
        guard let value = row.values[field] else { throw UIError("Table references an unknown record field.") }
        switch value {
        case .text(let text): return text
        case .number(let number):
          let text = String(number)
          return text.hasSuffix(".0") ? String(text.dropLast(2)) : text
        case .boolean(let value): return value ? "True" : "False"
        }
      }
    }
  }
}

public struct RecordSchema: Codable, Sendable {
  public let fields: [String: CalculationRegistry.ValueKind]

  public init(fields: [String: CalculationRegistry.ValueKind]) { self.fields = fields }

  private enum CodingKeys: String, CodingKey { case fields }
  public init(from decoder: any Decoder) throws {
    try checkKeys(decoder, allowed: ["fields"])
    let container = try decoder.container(keyedBy: CodingKeys.self)
    fields = try container.decode([String: CalculationRegistry.ValueKind].self, forKey: .fields)
  }

  public func validate(_ rows: [RecordRow]) throws {
    guard !fields.isEmpty, fields.count <= 16, fields.keys.allSatisfy(validIdentifier),
      rows.count <= 32, Set(rows.map(\.id)).count == rows.count else {
      throw UIError("Records require at most 32 unique rows and 1–16 declared fields.")
    }
    guard !fields.values.contains(.instant) else {
      throw UIError("Record fields support only text, number, and boolean kinds.")
    }
    for row in rows {
      guard validIdentifier(row.id), Set(row.values.keys) == Set(fields.keys) else {
        throw UIError("Record fields must match their declared schema.")
      }
      for (name, kind) in fields {
        switch (kind, row.values[name]) {
        case (.text, .text(let text)) where text.count <= 1000: break
        case (.number, .number(let number)) where number.isFinite && abs(number) <= 1e9: break
        case (.boolean, .boolean): break
        default: throw UIError("Invalid record value for '\(name)'.")
        }
      }
    }
  }
}
