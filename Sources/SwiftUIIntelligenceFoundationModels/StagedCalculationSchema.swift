import Foundation
import SwiftUIIntelligence

/// Splits finite native schemas and combines authored stages without adding document values.
enum NativeStagedSchema {
  private static let declarationKeys: Set<String> = ["state", "records", "calculations"]
  private static let layoutKeys: Set<String> = ["version", "root", "floatingActions"]

  static func declarationSchema(from data: Data) throws -> Data {
    try splitSchema(data, declarations: true)
  }

  static func layoutSchema(from data: Data) throws -> Data {
    try splitSchema(data, declarations: false)
  }

  static func layoutSchema(from data: Data, declarations: Data, signatures: [CalculationRegistry.Signature] = []) throws -> Data {
    var schema = try object(from: layoutSchema(from: data))
    let declared = try object(from: declarations)
    let state = declared["state"] as? [[String: Any]] ?? []
    let scalarIDs = state.compactMap { $0["id"] as? String }.sorted()
    let textIDs = state.filter { $0["kind"] as? String == "text" }.compactMap { $0["id"] as? String }.sorted()
    let numberIDs = state.filter { $0["kind"] as? String == "number" }.compactMap { $0["id"] as? String }.sorted()
    let calculations = declared["calculations"] as? [[String: Any]] ?? []
    let derivedIDs = Set(calculations.flatMap { ($0["outputs"] as? [String: String]).map { Array($0.values) } ?? [] })
    let controls = scalarIDs.filter { !derivedIDs.contains($0) }
    func restrict(_ value: Any, parent: String = "") -> Any {
      if var object = value as? [String: Any] {
        if parent == "properties" {
          for key in ["binding", "timeBinding", "detailBinding"] where object[key] != nil {
            let ids = key == "binding" ? scalarIDs : textIDs
            if ids.isEmpty { object.removeValue(forKey: key) }
            else { object[key] = ["type": "string", "enum": ids] }
          }
        }
        return object.reduce(into: [String: Any]()) { result, entry in
          result[entry.key] = restrict(entry.value, parent: entry.key)
        }
      }
      if let array = value as? [Any] { return array.map { restrict($0, parent: parent) } }
      return value
    }
    schema = restrict(schema) as! [String: Any]
    if var definitions = schema["$defs"] as? [String: [String: Any]] {
      for (name, ids) in [("text", textIDs), ("control", controls)] {
        guard var node = definitions[name], var fields = node["properties"] as? [String: Any] else { continue }
        if ids.isEmpty {
          if name == "control" {
            definitions.removeValue(forKey: "control")
            continue
          }
          fields.removeValue(forKey: "binding")
        } else { fields["binding"] = ["type": "string", "enum": ids] }
        node["properties"] = fields
        definitions[name] = node
      }
      // Metric value bindings reference numeric scalar state, not record projections.
      if var metric = definitions["metric"], var fields = metric["properties"] as? [String: Any],
        fields["valueBinding"] != nil {
        if numberIDs.isEmpty { fields.removeValue(forKey: "valueBinding") }
        else {
          fields["valueBinding"] = [
            "type": "string", "enum": numberIDs,
            "description": "State field ID to bind this metric to (select 'output_payable' for payable total)."
          ]
        }
        metric["properties"] = fields
        definitions["metric"] = metric
      }
      // Chart point bindings are numeric, not arbitrary scalar fields.
      if var chart = definitions["chart"], var fields = chart["properties"] as? [String: Any],
        var points = fields["points"] as? [String: Any], var item = points["items"] as? [String: Any],
        var pointFields = item["properties"] as? [String: Any] {
        if numberIDs.isEmpty { pointFields.removeValue(forKey: "binding") }
        else { pointFields["binding"] = ["type": "string", "enum": numberIDs] }
        item["properties"] = pointFields; points["items"] = item; fields["points"] = points
        chart["properties"] = fields; definitions["chart"] = chart
      }
      var collections = [String: [String: CalculationRegistry.ValueKind]]()
      for record in declared["records"] as? [[String: Any]] ?? [] {
        guard let id = record["id"] as? String, let declaration = record["schema"] as? [String: Any],
          let fields = declaration["fields"] as? [String: String] else { throw UIError("Invalid authored record schema.") }
        collections[id] = try fields.mapValues { name in
          guard let kind = CalculationRegistry.ValueKind(rawValue: name) else { throw UIError("Unknown record value kind.") }
          return kind
        }
      }
      for calculation in calculations {
        guard let capability = calculation["capability"] as? String,
          let signature = signatures.first(where: { $0.id == capability }) else {
          if (calculation["recordOutputs"] as? [String: String] ?? [:]).isEmpty { continue }
          throw UIError("A record output requires its registered signature.")
        }
        for (parameter, id) in calculation["recordOutputs"] as? [String: String] ?? [:] {
          guard let output = signature.recordOutputs[parameter] else { throw UIError("Unknown record output parameter.") }
          collections[id] = output.fields
        }
      }
      let collectionIDs = collections.keys.sorted()
      func restrictRecords(_ value: Any) -> Any {
        if var object = value as? [String: Any] {
          if var fields = object["properties"] as? [String: [String: Any]], fields["recordSource"] != nil {
            if collectionIDs.isEmpty {
              fields.removeValue(forKey: "recordSource"); fields.removeValue(forKey: "recordFields"); fields.removeValue(forKey: "editableFields")
            } else {
              let kind = (fields["type"]?["enum"] as? [String])?.first
              let textOnly = kind == "list" || kind == "timeline"
              let eligible = collections.filter { !textOnly || $0.value.values.contains(.text) }
              fields["recordSource"] = ["type": "string", "enum": eligible.keys.sorted()]
              let names = Set(eligible.values.flatMap { schema in schema.filter { !textOnly || $0.value == .text }.keys }).sorted()
              if names.isEmpty {
                fields.removeValue(forKey: "recordSource"); fields.removeValue(forKey: "recordFields")
              } else if var projection = fields["recordFields"] {
                projection["items"] = ["type": "string", "enum": names]; fields["recordFields"] = projection
              }
              if var editable = fields["editableFields"] {
                let sourceNames = Set((declared["records"] as? [[String: Any]] ?? []).flatMap {
                  ((($0["schema"] as? [String: Any])?["fields"] as? [String: String]) ?? [:]).keys
                }).sorted()
                if sourceNames.isEmpty { fields.removeValue(forKey: "editableFields") }
                else { editable["items"] = ["type": "string", "enum": sourceNames]; fields["editableFields"] = editable }
              }
            }
            object["properties"] = fields
          }
          return object.mapValues(restrictRecords)
        }
        if let array = value as? [Any] { return array.map(restrictRecords) }
        return value
      }
      definitions = restrictRecords(definitions) as! [String: [String: Any]]
      schema["$defs"] = definitions
    }
    return try encode(schema)
  }

  /// Supplies layout references without duplicating source rows already preserved for final assembly.
  static func layoutCatalog(declarations: Data, signatures: [CalculationRegistry.Signature] = []) throws -> Data {
    let source = try object(from: declarations)
    try validateKeys(source, allowed: declarationKeys, required: ["state", "calculations"])
    var catalog = source
    if let states = source["state"] as? [[String: Any]] {
      catalog["state"] = states.map { state in
        state.filter { ["id", "kind", "value"].contains($0.key) }
      }
    }
    if let records = source["records"] as? [[String: Any]] {
      catalog["records"] = records.map { record in record.filter { $0.key != "rows" } }
    }
    var derived = [[String: Any]]()
    for binding in source["calculations"] as? [[String: Any]] ?? [] {
      guard let capability = binding["capability"] as? String,
        let signature = signatures.first(where: { $0.id == capability }) else { continue }
      for (parameter, id) in binding["recordOutputs"] as? [String: String] ?? [:] {
        guard let schema = signature.recordOutputs[parameter] else { throw UIError("Unknown output collection parameter.") }
        derived.append(["id": id, "output": parameter, "fields": schema.fields.mapValues(\.rawValue), "editable": false])
      }
    }
    if !derived.isEmpty { catalog["derivedCollections"] = derived }
    return try encode(catalog)
  }

  /// Checks stage boundaries only. The caller validates declarations and the complete document separately.
  static func assemble(declarations: Data, layout: Data) throws -> Data {
    let declarationObject = try object(from: declarations)
    let layoutObject = try object(from: layout)
    try validateKeys(declarationObject, allowed: declarationKeys, required: ["state", "calculations"])
    try validateKeys(layoutObject, allowed: layoutKeys, required: layoutKeys)
    for key in declarationObject.keys {
      guard declarationObject[key] is [Any] else {
        throw UIError("The declaration section '\(key)' must be an array.")
      }
    }
    guard layoutObject["root"] is [String: Any], layoutObject["floatingActions"] is [Any] else {
      throw UIError("The layout requires a root object and a floatingActions array.")
    }
    var document = declarationObject
    for (key, value) in layoutObject {
      guard document[key] == nil else { throw UIError("Stage fields must not overlap.") }
      document[key] = value
    }
    let result = try encode(document)
    guard result.count <= 65_536 else { throw UIError("JSON exceeds the 64 KiB limit.") }
    return result
  }

  private static func splitSchema(_ data: Data, declarations: Bool) throws -> Data {
    var schema = try object(from: data)
    guard let properties = schema["properties"] as? [String: Any] else {
      throw UIError("The native schema requires top-level properties.")
    }
    try validateKeys(properties, allowed: declarationKeys.union(layoutKeys),
      required: ["state", "calculations", "version", "root", "floatingActions"])
    let keys = declarations ? declarationKeys : layoutKeys
    schema["properties"] = properties.filter { keys.contains($0.key) }
    var required = Set(schema["required"] as? [String] ?? []).intersection(keys)
    required.formUnion(declarations ? ["state", "calculations"] : layoutKeys)
    schema["required"] = required.sorted()
    schema["additionalProperties"] = false
    if declarations { schema.removeValue(forKey: "$defs") }
    return try encode(schema)
  }

  private static func validateKeys(_ object: [String: Any], allowed: Set<String>, required: Set<String>) throws {
    let keys = Set(object.keys)
    guard keys.isSubset(of: allowed), required.isSubset(of: keys) else {
      throw UIError("The stage has unknown or missing top-level fields.")
    }
    guard !object.values.contains(where: { $0 is NSNull }) else {
      throw UIError("Stage sections must not be null.")
    }
  }

  private static func object(from data: Data) throws -> [String: Any] {
    do {
      guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw UIError("The stage must be a JSON object.")
      }
      return object
    } catch let error as UIError {
      throw error
    } catch {
      throw UIError("Unable to decode stage JSON: \(error.localizedDescription)")
    }
  }

  private static func encode(_ object: [String: Any]) throws -> Data {
    try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
  }
}
