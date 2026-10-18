import Foundation
import SwiftUIIntelligence
@testable import SwiftUIIntelligenceFoundationModels
import Testing

@Suite struct NativeLayoutTopologyTests {
  private let kinds: Set<UINode.Kind> = [.vstack, .hstack, .grid, .section, .form, .text, .control, .metric, .list, .table, .chart, .timeline]

  private func node(_ id: String, _ parent: String = "", _ kind: String = "vstack") -> [String: Any] {
    ["id": id, "parentID": parent, "kind": kind]
  }

  private func batch(_ nodes: [[String: Any]], complete: Bool = false) throws -> Data {
    try JSONSerialization.data(withJSONObject: ["nodes": nodes, "complete": complete], options: [.sortedKeys])
  }

  @Test func rejectsTrailingCommasWithoutCommittingTopology() throws {
    for json in [
      #"{"nodes":[{"id":"root","parentID":"","kind":"vstack",}],"complete":true}"#,
      #"{"nodes":[{"id":"root","parentID":"","kind":"vstack"}, ],"complete":true}"#,
      #"{"nodes":[{"id":"root","parentID":"","kind":"vstack"}],"complete":true, }"#,
    ] {
      var topology = try NativeLayoutTopology(availableKinds: kinds)
      #expect(throws: UIError.self) { try topology.accept(Data(json.utf8)) }
      #expect(topology.nodes.isEmpty)
      #expect(!topology.isComplete)
    }
  }

  @Test func trailingCommasRejectAcrossEncodingsAndPreserveExistingPrefix() throws {
    for encoding: String.Encoding in [.utf8, .utf16, .utf32] {
      for whitespace in ["\t", "\n", "\r", " "] {
        var topology = try NativeLayoutTopology(availableKinds: kinds)
        try topology.accept(batch([node("root")]))
        let prefix = topology.nodes
        let text = #"{"nodes":[{"id":"child","parentID":"root","kind":"text"},"# + whitespace + #"],"complete":true}"#
        let bytes = try #require(text.data(using: encoding))
        #expect(throws: UIError.self) { try topology.accept(bytes) }
        #expect(topology.nodes == prefix)
        #expect(!topology.isComplete)
      }
    }
  }

  // Given an unavailable scope, initialization rejects empty and unsupported kind sets.
  @Test func rejectsInvalidScope() throws {
    #expect(throws: UIError.self) { try NativeLayoutTopology(availableKinds: []) }
    for kind: UINode.Kind in [.button, .navigationLink, .badge, .callout, .progress, .iconList] {
      #expect(throws: UIError.self) { try NativeLayoutTopology(availableKinds: [.text, kind]) }
    }
    for kind in kinds { _ = try NativeLayoutTopology(availableKinds: [kind]) }
  }

  // Given a valid prefix, invalid IDs, roots, and parents roll back the entire batch.
  @Test func rejectsInvalidTopologyAtomically() throws {
    var topology = try NativeLayoutTopology(availableKinds: kinds)
    try topology.accept(batch([node("root"), node("leaf", "root", "text")]))
    let prefix = topology.nodes
    let invalid = [
      node("" , "root"), node("a b", "root"), node("é", "root"),
      node(String(repeating: "x", count: 65), "root"), node("root", "root"),
      node("second"), node("self", "self"), node("orphan", "missing"),
      node("child", "leaf"), node("unknown", "root", "button"),
    ]
    for entry in invalid {
      #expect(throws: UIError.self) { try topology.accept(batch([node("pending", "root"), entry])) }
      #expect(topology.nodes == prefix)
      #expect(!topology.isComplete)
    }
    #expect(throws: UIError.self) {
      try topology.accept(batch([node("forward", "later"), node("later", "root")]))
    }
    #expect(throws: UIError.self) {
      try topology.accept(batch([node("repeat", "root"), node("repeat", "root")]))
    }
    var empty = try NativeLayoutTopology(availableKinds: kinds)
    #expect(throws: UIError.self) { try empty.accept(batch([node("child", "root")])) }
    #expect(empty.nodes.isEmpty)
    var scoped = try NativeLayoutTopology(availableKinds: [.vstack])
    #expect(throws: UIError.self) { try scoped.accept(batch([node("root"), node("leaf", "root", "text")])) }
    #expect(scoped.nodes.isEmpty)
    try topology.accept(batch([node(String(repeating: "A", count: 61) + "._-", "root")], complete: true))
  }

  // Given JSON outside the exact batch contract, rejection does not add defaults or mutate state.
  @Test func rejectsNoncanonicalBatchFields() throws {
    let invalid = [
      #"{}"#, #"[]"#, #"null"#, #"{"nodes":[]}"#, #"{"complete":true}"#,
      #"{"nodes":[null],"complete":true}"#,
      #"{"nodes":[{"id":"x","parentID":"root","kind":"unknown"}],"complete":true}"#, #"{"nodes":[],"complete":null}"#,
      #"{"nodes":[],"complete":0}"#, #"{"nodes":[],"complete":"true"}"#,
      #"{"nodes":null,"complete":true}"#, #"{"nodes":[],"complete":true,"extra":1}"#,
      #"{"nodes":[{"id":"x","parentID":"root","kind":"text","value":"no"}],"complete":true}"#,
      #"{"nodes":[{"id":"x","kind":"text"}],"complete":true}"#,
      #"{"nodes":[{"id":"x","parentID":null,"kind":"text"}],"complete":true}"#,
      #"{"nodes":[{"id":null,"parentID":"root","kind":"text"}],"complete":true}"#,
      #"{"nodes":[{"id":"x","parentID":"root","kind":null}],"complete":true}"#,
      #"{"nodes":[],"complete":false,"complete":true}"#,
      #"{"nodes":[],"nodes":[{"id":"x","parentID":"root","kind":"text"}],"complete":true}"#,
      #"{"nodes":[{"id":"x","id":"y","parentID":"root","kind":"text"}],"complete":true}"#,
      #"{"nodes":[{"id":"x","\u0069d":"y","parentID":"root","kind":"text"}],"complete":true}"#,
      #"{"nodes":[{"id":"x","parentID":"missing","parentID":"root","kind":"text"}],"complete":true}"#,
      #"{"nodes":[{"id":"x","parentID":"root","kind":"text","kind":"metric"}],"complete":true}"#,
      "{",
    ]
    for json in invalid {
      for encoding: String.Encoding in [.utf8, .utf16, .utf32] {
        var topology = try NativeLayoutTopology(availableKinds: kinds)
        try topology.accept(batch([node("root")]))
        let prefix = topology.nodes
        #expect(throws: UIError.self) { try topology.accept(try #require(json.data(using: encoding))) }
        #expect(topology.nodes == prefix)
        #expect(!topology.isComplete)
      }
    }
  }

  // Given batch limits and explicit completion, boundary calls reject without consuming a batch.
  @Test func enforcesBatchAndCompletionBounds() throws {
    var topology = try NativeLayoutTopology(availableKinds: kinds)
    #expect(throws: UIError.self) { try topology.accept(batch([], complete: true)) }
    #expect(throws: UIError.self) { try topology.accept(batch([])) }
    let oversized = [node("root")] + (1...16).map { node("n\($0)", "root") }
    #expect(throws: UIError.self) { try topology.accept(batch(oversized)) }
    #expect(topology.nodes.isEmpty)
    try topology.accept(batch([node("root")]))
    for index in 1...6 { try topology.accept(batch([node("n\(index)", "root")])) }
    let prefix = topology.nodes
    #expect(throws: UIError.self) { try topology.accept(batch([node("eighth", "root")])) }
    #expect(topology.nodes == prefix)
    try topology.accept(batch([], complete: true))
    #expect(topology.isComplete)
    #expect(throws: UIError.self) { try topology.accept(batch([], complete: true)) }
    #expect(throws: UIError.self) { try topology.accept(batch([node("late", "root")], complete: true)) }
    #expect(topology.nodes == prefix)
    var leafRoot = try NativeLayoutTopology(availableKinds: [.text])
    try leafRoot.accept(batch([node("root", "", "text")], complete: true))
    #expect(leafRoot.nodes.count == 1)
  }

  // Given twelve levels, a thirteenth level rejects atomically and a valid sibling can still complete.
  @Test func enforcesDepthBound() throws {
    var topology = try NativeLayoutTopology(availableKinds: kinds)
    let chain = (0..<12).map { node("n\($0)", $0 == 0 ? "" : "n\($0 - 1)") }
    try topology.accept(batch(chain))
    let prefix = topology.nodes
    #expect(throws: UIError.self) { try topology.accept(batch([node("tooDeep", "n11")], complete: true)) }
    #expect(topology.nodes == prefix)
    #expect(!topology.isComplete)
    try topology.accept(batch([node("sibling", "n10", "text")], complete: true))
    #expect(topology.nodes.count == 13)
  }

  // Given 32 direct children, child 33 rejects while another parent's child remains valid.
  @Test func enforcesChildBound() throws {
    var topology = try NativeLayoutTopology(availableKinds: kinds)
    try topology.accept(batch([node("root")] + (0..<15).map { node("c\($0)", "root") }))
    try topology.accept(batch((15..<31).map { node("c\($0)", "root") }))
    try topology.accept(batch([node("c31", "root")]))
    let prefix = topology.nodes
    #expect(throws: UIError.self) { try topology.accept(batch([node("c32", "root")], complete: true)) }
    #expect(topology.nodes == prefix)
    #expect(!topology.isComplete)
    try topology.accept(batch([node("nested", "c0")], complete: true))
  }

  // Given 32 leaf slots across parents, slot 33 rejects without changing completion or prefix.
  @Test func enforcesLeafSlotBound() throws {
    var topology = try NativeLayoutTopology(availableKinds: kinds)
    try topology.accept(batch([node("root"), node("left", "root"), node("right", "root")]))
    let leafKinds = ["text", "control", "metric", "list", "table", "chart", "timeline"]
    for start in [0, 16] {
      try topology.accept(batch((start..<(start + 16)).map {
        node("s\($0)", $0 < 16 ? "left" : "right", leafKinds[$0 % leafKinds.count])
      }))
    }
    let prefix = topology.nodes
    #expect(throws: UIError.self) { try topology.accept(batch([node("extra", "right", "text")], complete: true)) }
    #expect(topology.nodes == prefix)
    #expect(!topology.isComplete)
    try topology.accept(batch([], complete: true))
  }

  // Given eight full batches, exactly 128 nodes fit. Node 129 cannot fit either batch or completion limits.
  @Test func acceptsMaximumNodeCount() throws {
    var topology = try NativeLayoutTopology(availableKinds: kinds)
    let entries = (0..<128).map { index in
      node("n\(index)", index == 0 ? "" : "n\((index - 1) / 16)")
    }
    for batchIndex in 0..<7 {
      try topology.accept(batch(Array(entries[(batchIndex * 16)..<((batchIndex + 1) * 16)])))
    }
    let prefix = topology.nodes
    #expect(throws: UIError.self) {
      try topology.accept(batch(Array(entries[112..<128]) + [node("n128", "n7")], complete: true))
    }
    #expect(topology.nodes == prefix)
    try topology.accept(batch(Array(entries[112..<128]), complete: true))
    #expect(topology.nodes.count == 128)
    #expect(topology.isComplete)
    #expect(throws: UIError.self) { try topology.accept(batch([node("n128", "n7")], complete: true)) }
  }

  // Given two batches with interleaved siblings, acceptance preserves authored order and explicit completion.
  @Test func acceptsInterleavedSiblingsInExactOrder() throws {
    var topology = try NativeLayoutTopology(availableKinds: kinds)
    try topology.accept(batch([node("root"), node("left", "root"), node("right", "root"), node("a", "left", "text")]))
    #expect(!topology.isComplete)
    try topology.accept(batch([node("b", "right", "metric"), node("c", "left", "control")], complete: true))
    #expect(topology.nodes.map(\.id) == ["root", "left", "right", "a", "b", "c"])
    #expect(topology.nodes.map(\.parentID) == ["", "root", "root", "left", "right", "left"])
    #expect(topology.nodes.last?.kind == .control)
    #expect(topology.isComplete)
  }
}
