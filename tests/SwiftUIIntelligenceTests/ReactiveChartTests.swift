import Foundation
import Testing
import SwiftUIIntelligence

private let reactiveChartJSON = #"{"version":1,"state":[{"id":"amount","kind":"number","value":4,"minimum":-10,"maximum":10}],"root":{"id":"chart","type":"chart","title":"Amount","chartStyle":"donut","points":[{"label":"Share","series":"Amount","value":1,"binding":"amount"}]}}"#

@Test func reactiveChartDefaultsAndBindingKindsAreValidated() {
  for json in [reactiveChartJSON.replacingOccurrences(of: "\"value\":4", with: "\"value\":0"),
    reactiveChartJSON.replacingOccurrences(of: "\"binding\":\"amount\"", with: "\"binding\":\"missing\""),
    reactiveChartJSON.replacingOccurrences(of: "\"binding\":\"amount\"", with: "\"binding\":null")] {
    #expect(throws: UIError.self) { try UIDocument.decode(Data(json.utf8), registeredActions: []) }
  }
}

@Test @MainActor func invalidReplacementRetainsPreviousChartConfiguration() throws {
  let barJSON = reactiveChartJSON.replacingOccurrences(of: "\"chartStyle\":\"donut\"", with: "\"chartStyle\":\"bar\"")
  let bar = try UIDocument.decode(Data(barJSON.utf8), registeredActions: [])
  let donut = try UIDocument.decode(Data(reactiveChartJSON.utf8), registeredActions: [])
  let state = DocumentState()
  state.load(bar)
  try state.set("amount", to: .number(-1))
  state.load(donut)
  #expect(state.errorMessage != nil)
  #expect(state.values["amount"] == .number(-1))
  try state.set("amount", to: .number(-2))
  #expect(state.values["amount"] == .number(-2))
}

@Test @MainActor func reactiveChartRejectsInvalidCandidateBeforeStateCommit() throws {
  let document = try UIDocument.decode(Data(reactiveChartJSON.utf8), registeredActions: [])
  let state = DocumentState()
  state.load(document)
  #expect(state.values["amount"] == .number(4))
  #expect(try document.root.points[0].resolvedValue(in: state.values) == 4)
  #expect(throws: UIError.self) { try state.set("amount", to: .number(-1)) }
  #expect(throws: UIError.self) { try state.set("amount", to: .number(0)) }
  #expect(state.values["amount"] == .number(4))
  try state.set("amount", to: .number(7))
  #expect(try document.root.points[0].resolvedValue(in: state.values) == 7)
}
