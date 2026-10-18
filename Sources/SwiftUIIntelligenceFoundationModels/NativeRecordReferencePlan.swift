import Foundation
import SwiftUIIntelligence

/// Plans one authored collection per input. References stay within their capability namespace.
enum NativeRecordReferencePlan {
  struct Step: Sendable {
    let capabilityID: String
    let input: String
    let schema: RecordSchema
    let references: [RecordInputReference]
  }

  struct AcceptedCollection: Sendable {
    let originalData: Data
    let collection: RecordCollection
  }

  static func steps(signatures: [CalculationRegistry.Signature]) throws -> [Step] {
    guard Set(signatures.map(\.id)).count == signatures.count else {
      throw UIError("Record staging requires unique capability IDs.")
    }
    var result: [Step] = []
    for signature in signatures.sorted(by: { $0.id < $1.id }) {
      guard validID(signature.id), signature.recordInputs.keys.allSatisfy(validID) else {
        throw UIError("Record staging requires valid capability and input IDs.")
      }
      for schema in signature.recordInputs.values { try schema.validate([]) }
      var references: [String: [RecordInputReference]] = [:]
      var fields: [String: Set<String>] = [:]
      for reference in signature.recordReferences {
        guard signature.recordInputs[reference.input]?.fields[reference.field] == .text,
          signature.recordInputs[reference.targetInput] != nil,
          fields[reference.input, default: []].insert(reference.field).inserted else {
          throw UIError("Record references require known inputs and unique text fields.")
        }
        references[reference.input, default: []].append(reference)
      }
      var remaining = Set(signature.recordInputs.keys)
      var completed: Set<String> = []
      while !remaining.isEmpty {
        guard let input = remaining.sorted().first(where: { input in
          references[input, default: []].allSatisfy { completed.contains($0.targetInput) }
        }) else { throw UIError("Record input references must not contain cycles.") }
        result.append(Step(capabilityID: signature.id, input: input, schema: signature.recordInputs[input]!,
          references: references[input, default: []].sorted { $0.field < $1.field }))
        remaining.remove(input)
        completed.insert(input)
      }
    }
    return result
  }

  static func targetCatalog(for step: Step, accepted: [String: [String: RecordCollection]]) throws -> Data {
    var catalog: [String: RecordCollection] = [:]
    for reference in step.references {
      guard let target = accepted[step.capabilityID]?[reference.targetInput] else {
        throw UIError("A record reference requires an accepted target collection.")
      }
      catalog[reference.targetInput] = target
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(catalog)
  }

  static func schemaForStep(_ step: Step, accepted: [String: [String: RecordCollection]]) throws -> Data {
    try step.schema.validate([])
    let targets = try targetIDs(step, accepted: accepted)
    var values: [String: Any] = [:]
    var fields: [String: Any] = [:]
    for (name, kind) in step.schema.fields {
      fields[name] = ["type": "string", "enum": [kind.rawValue]]
      switch kind {
      case .text: values[name] = ["type": "string", "maxLength": 1000]
      case .number: values[name] = ["type": "number", "minimum": -1e9, "maximum": 1e9]
      case .boolean: values[name] = ["type": "boolean"]
      case .instant: throw UIError("Record fields do not support instant declarations.")
      }
    }
    for (field, ids) in targets where !ids.isEmpty {
      values[field] = ["type": "string", "enum": ids.sorted()]
    }
    let collectionID: [String: Any] = [
      "type": "string", "minLength": 1, "maxLength": 64, "pattern": "^[A-Za-z0-9._-]+$",
      "description": "Unique identifier for this \(step.input) record collection (e.g. '\(step.input)_collection'). Must be unique across all collections."
    ]
    let nonRefFields = step.schema.fields.filter { $0.value != .boolean && targets[$0.key] == nil }
    let maxRows: Int
    if targets.values.contains(where: \.isEmpty) {
      maxRows = 0
    } else if nonRefFields.isEmpty && !targets.isEmpty {
      let product = targets.values.reduce(1) { $0 * $1.count }
      maxRows = min(max(product, 1), 32)
    } else {
      maxRows = 32
    }
    let stepRowIdentifier: [String: Any] = [
      "type": "string", "minLength": 1, "maxLength": 64, "pattern": "^[A-Za-z0-9._-]+$",
      "description": "Sequential unique identifier for this row within '\(step.input)' (e.g. '\(step.input)_1', '\(step.input)_2', '\(step.input)_3'). Every single row must have a distinct unique row ID; never copy referenced entity IDs to this row ID."
    ]
    let schema = closed(["id": collectionID, "schema": closed(["fields": closed(fields)]),
      "rows": ["type": "array", "maxItems": maxRows,
        "items": closed(["id": stepRowIdentifier, "values": closed(values)])]])
    return try JSONSerialization.data(withJSONObject: schema, options: [.sortedKeys])
  }

  /// Validates the authored bytes without defaults, ID repair, or JSON re-encoding.
  static func normalizeCollection(_ data: Data, step: Step,
    accepted: [String: [String: RecordCollection]]) throws -> AcceptedCollection {
    guard data.count <= 65_536 else { throw UIError("JSON exceeds the 64 KiB limit.") }
    let targets = try targetIDs(step, accepted: accepted)
    let collection = try JSONDecoder().decode(RecordCollection.self, from: data)
    guard validID(collection.id), collection.schema.fields == step.schema.fields else {
      throw UIError("A record input requires an authored ID and its exact signature schema.")
    }
    var rowIDs = Set<String>()
    for row in collection.rows {
      guard rowIDs.insert(row.id).inserted else {
        throw UIError("Input '\(step.input)' has duplicate authored row ID '\(row.id)'. Author unique IDs; do not replace source facts.")
      }
    }
    try collection.schema.validate(collection.rows)
    for row in collection.rows {
      for value in row.values.values {
        if case .text(let text) = value, text.unicodeScalars.count > 1000 {
          throw UIError("Native record text exceeds the 1000-code-point limit.")
        }
      }
      for (field, ids) in targets {
        guard case .text(let id) = row.values[field], ids.contains(id) else {
          throw UIError("A record reference must identify an accepted target row.")
        }
      }
    }
    return AcceptedCollection(originalData: data, collection: collection)
  }

  private static func targetIDs(_ step: Step, accepted: [String: [String: RecordCollection]]) throws -> [String: Set<String>] {
    var targets: [String: Set<String>] = [:]
    for reference in step.references {
      guard reference.input == step.input, step.schema.fields[reference.field] == .text,
        targets[reference.field] == nil,
        let target = accepted[step.capabilityID]?[reference.targetInput] else {
        throw UIError("A record reference requires its accepted target in the same capability.")
      }
      try target.schema.validate(target.rows)
      targets[reference.field] = Set(target.rows.map(\.id))
    }
    return targets
  }

  private static var identifier: [String: Any] {
    ["type": "string", "minLength": 1, "maxLength": 64, "pattern": "^[A-Za-z0-9._-]+$"]
  }

  private static var collectionIdentifier: [String: Any] {
    ["type": "string", "minLength": 1, "maxLength": 64, "pattern": "^[A-Za-z0-9._-]+$",
     "description": "Unique identifier for this authored record collection. Must be unique across all collections."]
  }

  private static var rowIdentifier: [String: Any] {
    ["type": "string", "minLength": 1, "maxLength": 64, "pattern": "^[A-Za-z0-9._-]+$",
     "description": "Unique identifier for this row within this collection (e.g. 'r-1', 'r-2', 'r-3'). Each row must have a distinct unique row ID; do not reuse referenced entity IDs or repeat row IDs across rows."]
  }

  private static func closed(_ fields: [String: Any]) -> [String: Any] {
    ["type": "object", "additionalProperties": false, "properties": fields, "required": fields.keys.sorted()]
  }

  private static func validID(_ id: String) -> Bool {
    !id.isEmpty && id.utf8.count <= 64 && id.utf8.allSatisfy {
      (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || [45, 46, 95].contains($0)
    }
  }
}
