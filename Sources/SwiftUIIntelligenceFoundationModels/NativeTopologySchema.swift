import Foundation
import SwiftUIIntelligence

/// Experimental native guidance only. The topology acceptor enforces cross-node constraints.
enum NativeTopologySchema {
  static func batch(
    availableKinds: Set<UINode.Kind>,
    parentPolicy: NativeLayoutTopology.ParentPolicy = .orderedPrefix,
    acceptedNodes: [NativeLayoutTopology.Node] = []
  ) throws -> Data {
    let supported: Set<UINode.Kind> = [.vstack, .hstack, .grid, .section, .form, .text, .control, .metric, .list, .table, .chart, .timeline, .image]
    guard !availableKinds.isEmpty, availableKinds.isSubset(of: supported) else {
      throw UIError("Topology guidance requires available supported layout kinds.")
    }
    var parent: [String: Any] = ["type": "string", "maxLength": 64]
    if parentPolicy == .snapshotContainers {
      // Validate the ordered prefix before using authored IDs as schema enum values.
      var checked = try NativeLayoutTopology(availableKinds: availableKinds)
      for start in stride(from: 0, to: acceptedNodes.count, by: 16) {
        let end = min(start + 16, acceptedNodes.count)
        let entries = acceptedNodes[start..<end].map {
          ["id": $0.id, "parentID": $0.parentID, "kind": $0.kind.rawValue]
        }
        try checked.accept(JSONSerialization.data(withJSONObject: [
          "nodes": entries, "complete": end == acceptedNodes.count,
        ]))
      }
      let parents = acceptedNodes.filter {
        [.vstack, .hstack, .grid, .section, .form].contains($0.kind)
      }.map(\.id)
      guard acceptedNodes.isEmpty || !parents.isEmpty else {
        throw UIError("Snapshot guidance requires a previously accepted container.")
      }
      parent["enum"] = acceptedNodes.isEmpty ? [""] : parents
    }
    let node = object([
      "id": ["type": "string", "minLength": 1, "maxLength": 64, "pattern": "^[A-Za-z0-9._-]+$"],
      "parentID": parent,
      "kind": ["type": "string", "enum": availableKinds.map(\.rawValue).sorted()],
    ])
    var nodes: [String: Any] = ["type": "array", "maxItems": 16, "items": node]
    if parentPolicy == .snapshotContainers && acceptedNodes.isEmpty {
      nodes["minItems"] = 1
      nodes["maxItems"] = 1
    }
    return try JSONSerialization.data(withJSONObject: object([
      "nodes": nodes,
      "complete": ["type": "boolean"],
    ]), options: [.sortedKeys])
  }

  static func payload(kind: UINode.Kind, id: String) throws -> Data {
    guard !id.isEmpty, id.utf8.count <= 64,
      id.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || [45, 46, 95].contains($0) }) else {
      throw UIError("A topology payload requires an authored valid ID.")
    }
    let containers: Set<UINode.Kind> = [.vstack, .hstack, .grid, .section, .form]
    let leaves: Set<UINode.Kind> = [.text, .control, .metric, .list, .table, .chart, .timeline, .image]
    guard containers.contains(kind) || leaves.contains(kind) else { throw UIError("Unsupported topology payload kind.") }
    var fields: [String: Any] = ["id": ["type": "string", "enum": [id]]]
    var required = ["id"]
    if containers.contains(kind) {
      fields["spacing"] = ["type": "number", "minimum": 0, "maximum": 48]
      if kind == .grid {
        fields["columnCount"] = ["type": "integer", "minimum": 1, "maximum": 6]
        required.append("columnCount")
      }
      if kind == .section || kind == .form {
        fields["title"] = ["type": "string", "minLength": 1, "maxLength": 160]
        fields["icon"] = ["type": "string", "minLength": 1, "maxLength": 64, "pattern": "^[A-Za-z0-9._-]+$"]
        required.append("title")
      }
    } else {
      fields["mode"] = ["type": "string", "enum": [.list, .table, .chart, .timeline].contains(kind) ? ["static", "records"] : ["static"]]
      fields["purpose"] = ["type": "string", "minLength": 1, "maxLength": 500]
      required += ["mode", "purpose"]
    }
    return try JSONSerialization.data(withJSONObject: ["type": "object", "additionalProperties": false,
      "properties": fields, "required": required.sorted()], options: [.sortedKeys])
  }

  private static func object(_ fields: [String: Any]) -> [String: Any] {
    ["type": "object", "additionalProperties": false, "properties": fields, "required": fields.keys.sorted()]
  }
}
