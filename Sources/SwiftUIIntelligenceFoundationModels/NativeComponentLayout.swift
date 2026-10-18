import Foundation
import SwiftUIIntelligence

/// Extracts one leaf schema without selecting component values or adding layout nodes.
enum NativeComponentLayout {
  static func componentSchema(from data: Data, kind: UINode.Kind, projected: Bool) throws -> Data {
    guard [.text, .control, .metric, .list, .table, .chart, .timeline].contains(kind) else {
      throw UIError("Component generation requires a supported leaf kind.")
    }
    guard kind != .metric || !projected else {
      throw UIError("Metric components support static mode only; valueBinding is a scalar reference, not a record projection.")
    }
    let decoded: Any
    do { decoded = try JSONSerialization.jsonObject(with: data) }
    catch { throw UIError("Unable to decode the component schema.") }
    guard let schema = decoded as? [String: Any],
      var definitions = schema["$defs"] as? [String: [String: Any]],
      let component = definitions[kind.rawValue] else {
      throw UIError("The layout schema does not contain the requested component kind.")
    }
    definitions[kind.rawValue] = try componentDefinition(component, kind: kind, projected: projected)
    var retained = [String: [String: Any]]()
    var pending = [kind.rawValue]
    while let name = pending.popLast() {
      if retained[name] != nil { continue }
      guard let definition = definitions[name] else {
        throw UIError("The component schema contains a missing reference.")
      }
      retained[name] = definition
      pending.append(contentsOf: try references(in: definition))
    }
    return try JSONSerialization.data(withJSONObject: [
      "$ref": "#/$defs/\(kind.rawValue)", "$defs": retained,
    ], options: [.sortedKeys])
  }

  private static func componentDefinition(_ definition: [String: Any], kind: UINode.Kind,
    projected: Bool) throws -> [String: Any] {
    var result = definition
    if let branches = definition["anyOf"] as? [[String: Any]] {
      guard !branches.isEmpty else { throw UIError("The component schema requires a kind definition.") }
      result["anyOf"] = try branches.map { try componentDefinition($0, kind: kind, projected: projected) }
      return result
    }
    guard var fields = definition["properties"] as? [String: [String: Any]],
      fields["type"]?["enum"] as? [String] == [kind.rawValue] else {
      throw UIError("The component schema must specify exactly the requested kind.")
    }
    var required = Set(definition["required"] as? [String] ?? [])
    if projected {
      guard fields["recordSource"] != nil, fields["recordFields"] != nil else {
        throw UIError("The component schema does not support record projection.")
      }
      required.formUnion(["recordSource", "recordFields"])
    } else {
      for key in ["recordSource", "recordFields", "editableFields"] {
        fields.removeValue(forKey: key)
        required.remove(key)
      }
    }
    result["properties"] = fields
    result["required"] = required.sorted()
    return result
  }

  private static func references(in value: Any) throws -> [String] {
    if let object = value as? [String: Any] {
      var names = [String]()
      if let reference = object["$ref"] {
        guard let reference = reference as? String, reference.hasPrefix("#") else {
          throw UIError("The component schema requires local definition references.")
        }
        guard let decoded = String(reference.dropFirst()).removingPercentEncoding,
          decoded.hasPrefix("/$defs/") else { throw UIError("Invalid definition URI fragment.") }
        let token = String(decoded.dropFirst("/$defs/".count))
        guard !token.isEmpty, !token.contains("/") else {
          throw UIError("The component schema requires direct definition references.")
        }
        var name = ""
        var index = token.startIndex
        while index < token.endIndex {
          let character = token[index]
          index = token.index(after: index)
          if character == "~" {
            guard index < token.endIndex, token[index] == "0" || token[index] == "1" else {
              throw UIError("Invalid JSON Pointer escape in definition reference.")
            }
            name.append(token[index] == "0" ? "~" : "/")
            index = token.index(after: index)
          } else { name.append(character) }
        }
        names.append(name)
      }
      for child in object.values { names.append(contentsOf: try references(in: child)) }
      return names
    }
    if let array = value as? [Any] { return try array.flatMap { try references(in: $0) } }
    return []
  }
}
