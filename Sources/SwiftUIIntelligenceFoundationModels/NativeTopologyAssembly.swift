import Foundation
import SwiftUIIntelligence

/// Reconstructs only model-authored topology and payloads; final plan validation remains authoritative.
enum NativeTopologyAssembly {
  static func assemble(topology: NativeLayoutTopology, payloads: [String: Data],
    requirements: DocumentRequirements = .init()) throws -> Data {
    guard topology.isComplete, let root = topology.nodes.first,
      Set(payloads.keys) == Set(topology.nodes.map(\.id)) else {
      throw UIError("A complete topology requires exactly one payload per authored node.")
    }
    let containers: Set<UINode.Kind> = [.vstack, .hstack, .grid, .section, .form]
    func build(_ node: NativeLayoutTopology.Node) throws -> [String: Any] {
      guard let data = payloads[node.id] else { throw UIError("Missing topology payload.") }
      try NativeLayoutTopology.validateJSONSyntax(data)
      guard var payload = try JSONSerialization.jsonObject(with: data) as? [String: Any],
        payload["id"] as? String == node.id else { throw UIError("Payload ID must match its topology node.") }
      if containers.contains(node.kind) {
        var allowed: Set<String> = ["id", "spacing"]
        if node.kind == .grid { allowed.insert("columnCount") }
        if node.kind == .section || node.kind == .form { allowed.formUnion(["title", "icon"]) }
        guard Set(payload.keys).isSubset(of: allowed) else { throw UIError("Unknown container payload field.") }
        payload["type"] = node.kind.rawValue
        payload["children"] = try topology.nodes.filter { $0.parentID == node.id }.map(build)
      } else {
        guard Set(payload.keys) == ["id", "mode", "purpose"] else { throw UIError("A leaf payload requires only id, mode, and purpose.") }
        payload["type"] = "slot"
        payload["componentType"] = node.kind.rawValue
      }
      return payload
    }
    let native = try JSONSerialization.data(withJSONObject: ["version": 1, "root": build(root), "floatingActions": []], options: [.sortedKeys])
    let normalized = try NativeLayoutSlots.normalizeNativePlan(native)
    _ = try NativeLayoutSlots.validatePlan(normalized, requirements: requirements)
    return normalized
  }
}
