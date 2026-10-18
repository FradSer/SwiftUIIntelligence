import Foundation
import SwiftUIIntelligence

/// Experimental orchestration seam. This helper does not publish previews or call a model.
enum NativeTopologyPlanner {
  static func run(
    availableKinds: Set<UINode.Kind>,
    requirements: DocumentRequirements,
    parentPolicy: NativeLayoutTopology.ParentPolicy = .orderedPrefix,
    generateBatch: @Sendable (Data, Data, Int) async throws -> Data,
    generatePayload: @Sendable (NativeLayoutTopology.Node, Data, Data) async throws -> Data
  ) async throws -> Data {
    try Task.checkCancellation()
    var topology = try NativeLayoutTopology(availableKinds: availableKinds, parentPolicy: parentPolicy)
    // Eight calls permit 128 ordered-prefix nodes, or 113 snapshot nodes at depth at most eight.
    for batchIndex in 1...8 {
      let batchSchema = try NativeTopologySchema.batch(
        availableKinds: availableKinds, parentPolicy: parentPolicy, acceptedNodes: topology.nodes)
      let prefix = try serialize(topology.nodes)
      try Task.checkCancellation()
      let batch: Data
      do {
        batch = try await generateBatch(batchSchema, prefix, batchIndex)
      } catch {
        try Task.checkCancellation()
        if error is CancellationError { throw CancellationError() }
        throw UIError("Native topology batch \(batchIndex) generation failed.")
      }
      try Task.checkCancellation()
      do { try topology.accept(batch) }
      catch { throw UIError("Native topology batch \(batchIndex) validation failed.") }
      if topology.isComplete { break }
    }
    let kinds = Set(topology.nodes.map(\.kind))
    guard requirements.components.union(requirements.projectedComponents).isSubset(of: kinds),
      topology.nodes.filter({ $0.kind == .control }).count >= requirements.controls.count else {
      throw UIError("Native topology omits host-required component kinds or controls.")
    }
    let frozenTopology = try serialize(topology.nodes)
    var payloads: [String: Data] = [:]
    for (index, node) in topology.nodes.enumerated() {
      let schema = try NativeTopologySchema.payload(kind: node.kind, id: node.id)
      try Task.checkCancellation()
      let payload: Data
      do {
        payload = try await generatePayload(node, schema, frozenTopology)
      } catch {
        try Task.checkCancellation()
        if error is CancellationError { throw CancellationError() }
        throw UIError("Native topology payload \(index + 1) generation failed.")
      }
      try Task.checkCancellation()
      payloads[node.id] = payload
    }
    return try NativeTopologyAssembly.assemble(topology: topology, payloads: payloads, requirements: requirements)
  }

  private static func serialize(_ nodes: [NativeLayoutTopology.Node]) throws -> Data {
    try JSONSerialization.data(withJSONObject: nodes.map {
      ["id": $0.id, "parentID": $0.parentID, "kind": $0.kind.rawValue]
    }, options: [.sortedKeys])
  }
}
