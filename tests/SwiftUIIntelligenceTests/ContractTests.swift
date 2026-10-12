import Foundation
import Testing

@testable import SwiftUIIntelligence

// Given constrained JSON, when decoded, then IDs and native node types survive.
@Test func validDocumentHasStableIDs() throws {
  let json =
    #"{"version":1,"root":{"id":"root","type":"vstack","children":[{"id":"title","type":"text","text":"Hello","style":"title"}]},"floatingActions":[{"id":"hello","type":"button","title":"Say hello","action":"greet"}]}"#
  let first = try UIDocument.decode(Data(json.utf8), registeredActions: ["greet"])
  let second = try UIDocument.decode(Data(json.utf8), registeredActions: ["greet"])
  #expect(first.root.children.map(\.id) == second.root.children.map(\.id))
  #expect(first.floatingActions.first?.action == "greet")
}

// Given untrusted input, when it violates the contract, then decoding returns an error.
@Test(arguments: [
  "{",  // bad JSON
  #"{"version":1,"root":{"id":"r","type":"webview","url":"https://example.com"}}"#,
  #"{"version":1,"root":{"id":"r","type":"text","text":42}}"#,
  #"{"version":1,"root":{"id":"r","type":"vstack","spacing":-1,"children":[]}}"#,
  #"{"version":1,"root":{"id":"r","type":"button","title":"Run","action":"shell"}}"#,
  #"{"version":1,"root":{"id":"r","type":"button","title":"Run","action":"greet","params":{"command":"rm"}}}"#,
  #"{"version":1,"root":{"id":"r","type":"text","text":"Hi","style":"giant"}}"#,
  #"{"version":2,"root":{"id":"r","type":"text","text":"Hi"}}"#,
  #"{"version":1,"root":{"id":"r","type":"vstack","children":[{"id":"r","type":"text","text":"Hi"}]}}"#,
  #"{"version":1,"root":{"id":"r","type":"text","text":"Hi"},"floatingActions":[{"id":"t","type":"text","text":"No"}]}"#,
  #"{"version":1,"root":{"id":"r","type":"text","text":"Hi"},"code":"print(1)"}"#,
]) func invalidInputIsRejected(json: String) {
  #expect(throws: UIError.self) {
    try UIDocument.decode(Data(json.utf8), registeredActions: ["greet"])
  }
}

// Given an action registry, only the registered closure runs; unknown actions return errors.
@Test @MainActor func callbacksAreAllowlisted() throws {
  var calls = 0
  let registry = ActionRegistry([
    "greet": {
      calls += 1
      return "Hello from host"
    }
  ])
  #expect(try registry.perform("greet") == "Hello from host")
  #expect(calls == 1)
  #expect(throws: UIError.self) { try registry.perform("shell") }
  #expect(calls == 1)
}

@Test func resourceLimitsRejectOversizedAndDeepInput() {
  #expect(throws: UIError.self) {
    try UIDocument.decode(Data(repeating: 32, count: 65_537), registeredActions: [])
  }
  var node = #"{"id":"leaf","type":"text","text":"Hi"}"#
  for index in 0..<20 {
    node = "{\"id\":\"n\(index)\",\"type\":\"vstack\",\"children\":[\(node)]}"
  }
  let deepJSON = "{\"version\":1,\"root\":\(node)}"
  #expect(throws: UIError.self) {
    try UIDocument.decode(Data(deepJSON.utf8), registeredActions: [])
  }
}

@Test func allStructuralLimitsAreEnforced() throws {
  func rejected(_ root: [String: Any]) throws {
    let data = try JSONSerialization.data(withJSONObject: ["version": 1, "root": root])
    #expect(throws: UIError.self) { try UIDocument.decode(data, registeredActions: ["greet"]) }
  }
  try rejected(["id": "bad id", "type": "text", "text": "Hi"])
  try rejected(["id": String(repeating: "a", count: 65), "type": "text", "text": "Hi"])
  try rejected(["id": "r", "type": "text", "text": String(repeating: "a", count: 4_001)])
  try rejected([
    "id": "r", "type": "button", "title": String(repeating: "a", count: 81), "action": "greet",
  ])
  try rejected(["id": "r", "type": "button", "title": " ", "action": "greet"])
  try rejected(["id": "r", "type": "vstack", "children": [], "spacing": NSNull()])
  let children = (0..<33).map { ["id": "t\($0)", "type": "text", "text": "Hi"] }
  try rejected(["id": "r", "type": "hstack", "children": children])
  let groups = (0..<5).map { group in
    [
      "id": "g\(group)", "type": "vstack",
      "children": (0..<26).map {
        ["id": "t\(group)-\($0)", "type": "text", "text": "Hi"]
      },
    ] as [String: Any]
  }
  try rejected(["id": "r", "type": "vstack", "children": groups])
}

@Test @MainActor func hostErrorsRemainRecoverable() {
  let registry = ActionRegistry(["fail": { throw UIError("Host refused the request.") }])
  #expect(throws: UIError.self) { try registry.perform("fail") }
}
