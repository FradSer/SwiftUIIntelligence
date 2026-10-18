import Foundation
import Testing
import SwiftUIIntelligence

@Test @MainActor func timelineEventReadsValidatedBoundTimeAndDetail() throws {
  let json = #"{"version":1,"state":[{"id":"time","kind":"text","value":"18:30"},{"id":"detail","kind":"text","value":"Prepare 3 portions"}],"root":{"id":"timeline","type":"timeline","title":"Plan","events":[{"time":"Pending","title":"Prepare","detail":"Pending","timeBinding":"time","detailBinding":"detail"}]}}"#
  let document = try UIDocument.decode(Data(json.utf8), registeredActions: [])
  let state = DocumentState()
  state.load(document)
  let event = document.root.events[0]
  #expect(try event.resolvedTime(in: state.values) == "18:30")
  try state.set("time", to: .text("19:00"))
  try state.set("detail", to: .text("Prepare 5 portions"))
  #expect(try event.resolvedTime(in: state.values) == "19:00")
  #expect(try event.resolvedDetail(in: state.values) == "Prepare 5 portions")
  #expect(throws: UIError.self) { try state.set("time", to: .text("")) }
  #expect(throws: UIError.self) { try state.set("detail", to: .text(String(repeating: "x", count: 1001))) }
  #expect(state.values["time"] == .text("19:00"))
  let canonical = try DocumentGenerationContract.canonicalJSON(document)
  let again = try UIDocument.decode(canonical, registeredActions: [])
  #expect(again.root.events[0].timeBinding == "time")
  for invalid in [json.replacingOccurrences(of: "\"timeBinding\":\"time\"", with: "\"timeBinding\":null"),
    json.replacingOccurrences(of: "\"detailBinding\":\"detail\"", with: "\"detailBinding\":\"unknown\"")] {
    #expect(throws: UIError.self) { try UIDocument.decode(Data(invalid.utf8), registeredActions: []) }
  }
}
