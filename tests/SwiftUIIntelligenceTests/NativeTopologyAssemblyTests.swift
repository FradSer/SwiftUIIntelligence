import Foundation
import SwiftUIIntelligence
@testable import SwiftUIIntelligenceFoundationModels
import Testing

@Test func topologyPayloadRejectsDuplicateMembersAndTrailingCommas() throws {
  var topology = try NativeLayoutTopology(availableKinds: [.text])
  try topology.accept(Data(#"{"nodes":[{"id":"note","parentID":"","kind":"text"}],"complete":true}"#.utf8))
  for json in [
    #"{"id":"note","mode":"static","purpose":"First","purpose":"Second"}"#,
    #"{"id":"note","id":"note","mode":"static","purpose":"Exact"}"#,
    #"{"id":"note","mode":"static","purpose":"First","purpos\u0065":"Second"}"#,
    #"{"id":"note","mode":"static","purpose":"Exact", }"#,
  ] {
    #expect(throws: UIError.self) { try NativeTopologyAssembly.assemble(topology: topology, payloads: ["note": Data(json.utf8)]) }
  }
}

@Test func topologyPayloadRejectsOverlongUnicodePurposeWithoutTrimming() throws {
  var topology = try NativeLayoutTopology(availableKinds: [.text])
  try topology.accept(Data(#"{"nodes":[{"id":"note","parentID":"","kind":"text"}],"complete":true}"#.utf8))
  for pairs in [250, 251] {
    let data = try JSONSerialization.data(withJSONObject: ["id": "note", "mode": "static", "purpose": String(repeating: "e\u{301}", count: pairs)])
    if pairs == 250 { _ = try NativeTopologyAssembly.assemble(topology: topology, payloads: ["note": data]) }
    else { #expect(throws: UIError.self) { try NativeTopologyAssembly.assemble(topology: topology, payloads: ["note": data]) } }
  }
}

@Test func topologyAssemblyRejectsMissingOrAlteredPayloads() throws {
  var topology = try NativeLayoutTopology(availableKinds: [.grid, .text])
  try topology.accept(Data(#"{"nodes":[{"id":"root","parentID":"","kind":"grid"},{"id":"note","parentID":"root","kind":"text"}],"complete":true}"#.utf8))
  let valid = ["root": Data(#"{"id":"root","columnCount":2}"#.utf8), "note": Data(#"{"id":"note","mode":"static","purpose":"Exact supplied note"}"#.utf8)]
  for replacement in [#"{"id":"root"}"#, #"{"id":"other","columnCount":2}"#, #"{"id":"root","columnCount":2,"children":[]}"#, #"{"id":"root","columnCount":true}"#, #"{"id":"root","columnCount":2,"spacing":null}"#] {
    var payloads = valid; payloads["root"] = Data(replacement.utf8)
    #expect(throws: UIError.self) { try NativeTopologyAssembly.assemble(topology: topology, payloads: payloads) }
  }
  var missing = valid; missing.removeValue(forKey: "note")
  #expect(throws: UIError.self) { try NativeTopologyAssembly.assemble(topology: topology, payloads: missing) }
  var altered = valid; altered["note"] = Data(#"{"id":"note","mode":"records","purpose":"Wrong text mode"}"#.utf8)
  #expect(throws: UIError.self) { try NativeTopologyAssembly.assemble(topology: topology, payloads: altered) }
  #expect(throws: UIError.self) { try NativeTopologyAssembly.assemble(topology: topology, payloads: valid, requirements: .init(projectedComponents: [.table])) }
}

@Test func flatTopologyPreservesAuthoredPropertiesAndSiblingOrder() throws {
  var topology = try NativeLayoutTopology(availableKinds: [.vstack, .section, .table, .text])
  try topology.accept(Data(#"{"nodes":[{"id":"root","parentID":"","kind":"vstack"},{"id":"group","parentID":"root","kind":"section"},{"id":"reference","parentID":"root","kind":"table"}],"complete":false}"#.utf8))
  try topology.accept(Data(#"{"nodes":[{"id":"result","parentID":"group","kind":"table"},{"id":"note","parentID":"group","kind":"text"}],"complete":true}"#.utf8))
  let payloads = ["root": #"{"id":"root"}"#, "group": #"{"id":"group","title":"Exact group","spacing":7.5}"#,
    "reference": #"{"id":"reference","mode":"static","purpose":"Supplied reference table"}"#,
    "result": #"{"id":"result","mode":"records","purpose":"Computed rows"}"#,
    "note": #"{"id":"note","mode":"static","purpose":"Preserve exceptions"}"#].mapValues { Data($0.utf8) }
  let plan = try NativeTopologyAssembly.assemble(topology: topology, payloads: payloads, requirements: .init(projectedComponents: [.table]))
  let validated = try NativeLayoutSlots.validatePlan(plan, requirements: .init(projectedComponents: [.table]))
  #expect(validated.slots.map(\.id) == ["result", "note", "reference"])
  #expect(validated.slots.map(\.projected) == [true, false, false])
  let object = try #require(JSONSerialization.jsonObject(with: plan) as? [String: Any])
  let root = try #require(object["root"] as? [String: Any])
  #expect(root["spacing"] == nil)
  let children = try #require(root["children"] as? [[String: Any]])
  #expect(children.compactMap { $0["id"] as? String } == ["group", "reference"])
  #expect(children[0]["title"] as? String == "Exact group")
  #expect(children[0]["spacing"] as? Double == 7.5)
}
