import Foundation
import SwiftUIIntelligence
@_spi(Testing) @testable import SwiftUIIntelligenceFoundationModels
import Testing

@Suite struct NativeTopologySnapshotTests {
  private func batch(_ nodes: String, complete: Bool = false) -> Data {
    Data("{\"nodes\":\(nodes),\"complete\":\(complete)}".utf8)
  }

  // Given a frozen prefix, when a batch adds its own parent, then rejection rolls back all nodes.
  @Test func snapshotParentsAreAtomicAndAvailableNextBatch() throws {
    var topology = try NativeLayoutTopology(availableKinds: [.vstack, .text], parentPolicy: .snapshotContainers)
    try topology.accept(batch(#"[{"id":"root","parentID":"","kind":"vstack"}]"#))
    let prefix = topology.nodes
    #expect(throws: UIError.self) {
      try topology.accept(batch(#"[{"id":"group","parentID":"root","kind":"vstack"},{"id":"note","parentID":"group","kind":"text"}]"#))
    }
    #expect(topology.nodes == prefix)
    #expect(!topology.isComplete)
    try topology.accept(batch(#"[{"id":"group","parentID":"root","kind":"vstack"},{"id":"leaf","parentID":"root","kind":"text"}]"#))
    let data = try NativeTopologySchema.batch(availableKinds: [.vstack, .text], parentPolicy: .snapshotContainers, acceptedNodes: topology.nodes)
    #expect(try FoundationModelsDocumentProvider.validateNativeLayoutSchema(data))
    let schema = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let properties = try #require(schema["properties"] as? [String: Any])
    let nodes = try #require(properties["nodes"] as? [String: Any])
    let item = try #require(nodes["items"] as? [String: Any])
    let fields = try #require(item["properties"] as? [String: Any])
    let parent = try #require(fields["parentID"] as? [String: Any])
    #expect(parent["enum"] as? [String] == ["root", "group"])
    #expect(throws: UIError.self) {
      try topology.accept(batch(#"[{"id":"invalid","parentID":"leaf","kind":"text"}]"#, complete: true))
    }
    try topology.accept(batch(#"[{"id":"note","parentID":"group","kind":"text"}]"#, complete: true))
    #expect(topology.isComplete)
    #expect(topology.nodes.map(\.id) == ["root", "group", "leaf", "note"])
  }

  // Given an empty snapshot, when the root cannot continue, then only explicit completion is valid.
  @Test func snapshotRootMustBeSingleAndIncompleteRootMustBeContainer() throws {
    var topology = try NativeLayoutTopology(availableKinds: [.vstack, .text], parentPolicy: .snapshotContainers)
    #expect(throws: UIError.self) {
      try topology.accept(batch(#"[{"id":"note","parentID":"","kind":"text"}]"#))
    }
    #expect(throws: UIError.self) {
      try topology.accept(batch(#"[{"id":"root","parentID":"","kind":"vstack"},{"id":"note","parentID":"root","kind":"text"}]"#, complete: true))
    }
    #expect(topology.nodes.isEmpty)
    try topology.accept(batch(#"[{"id":"note","parentID":"","kind":"text"}]"#, complete: true))
    #expect(topology.isComplete)
  }

  private actor Calls {
    var batches = 0
    var payloads = 0
    func batch() { batches += 1 }
    func payload() { payloads += 1 }
    func counts() -> [Int] { [batches, payloads] }
  }

  // Given eight snapshot calls, when the last is unfinished, then no payload can run.
  @Test(arguments: [false, true])
  func runnerBoundsSnapshotToEightCallsAnd113Nodes(complete: Bool) async throws {
    let calls = Calls()
    do {
      _ = try await NativeTopologyPlanner.run(availableKinds: [.vstack], requirements: .init(), parentPolicy: .snapshotContainers,
        generateBatch: { schema, prefix, index in
          await calls.batch()
          #expect(try FoundationModelsDocumentProvider.validateNativeLayoutSchema(schema))
          let accepted = try #require(JSONSerialization.jsonObject(with: prefix) as? [[String: String]])
          #expect(accepted.count == (index == 1 ? 0 : 1 + (index - 2) * 16))
          let entries = (0..<(index == 1 ? 1 : 16)).map { offset -> [String: String] in
            let number = index == 1 ? 0 : 1 + (index - 2) * 16 + offset
            let parent = index == 1 ? "" : index == 2 ? "n0" : "n\(1 + (index - 3) * 16 + offset)"
            return ["id": "n\(number)", "parentID": parent, "kind": "vstack"]
          }
          return try JSONSerialization.data(withJSONObject: ["nodes": entries, "complete": complete && index == 8])
        }, generatePayload: { node, _, frozen in
          await calls.payload()
          let nodes = try #require(JSONSerialization.jsonObject(with: frozen) as? [[String: String]])
          #expect(nodes.count == 113)
          return try JSONSerialization.data(withJSONObject: ["id": node.id])
        })
      #expect(complete)
    } catch {
      #expect(!complete)
      #expect(error.localizedDescription.contains("batch 8"))
    }
    #expect(await calls.counts() == [8, complete ? 113 : 0])
  }

  // Given unchecked or exhausted prefixes, when guidance is requested, then no invalid enum is emitted.
  @Test func schemaRejectsInvalidPrefixesAndNoContainers() throws {
    for prefix: [NativeLayoutTopology.Node] in [
      [.init(id: "bad id", parentID: "", kind: .vstack)],
      [.init(id: "root", parentID: "missing", kind: .vstack)],
      [.init(id: "leaf", parentID: "", kind: .text)],
    ] {
      #expect(throws: UIError.self) {
        try NativeTopologySchema.batch(availableKinds: [.vstack, .text], parentPolicy: .snapshotContainers, acceptedNodes: prefix)
      }
    }
  }

  // Given an empty snapshot, when guidance is built, then it permits exactly one root.
  @Test func rootSchemaRequiresOneNodeAndConverts() throws {
    let data = try NativeTopologySchema.batch(availableKinds: [.vstack, .text], parentPolicy: .snapshotContainers)
    #expect(try FoundationModelsDocumentProvider.validateNativeLayoutSchema(data))
    let schema = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let properties = try #require(schema["properties"] as? [String: Any])
    let nodes = try #require(properties["nodes"] as? [String: Any])
    #expect(nodes["minItems"] as? Int == 1)
    #expect(nodes["maxItems"] as? Int == 1)
    let item = try #require(nodes["items"] as? [String: Any])
    let fields = try #require(item["properties"] as? [String: Any])
    let parent = try #require(fields["parentID"] as? [String: Any])
    #expect(parent["enum"] as? [String] == [""])
  }
}
