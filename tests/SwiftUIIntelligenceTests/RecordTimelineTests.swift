import Foundation
import Testing
import SwiftUIIntelligence

@Test @MainActor func timelineProjectsVariableStepRecords() throws {
  let json = #"{"version":1,"records":[{"id":"steps","schema":{"fields":{"start":"text","title":"text","detail":"text"}},"rows":[{"id":"cook","values":{"start":"18:30","title":"Cook lentils","detail":"30 minutes"}}]}],"root":{"id":"timeline","type":"timeline","title":"Plan","events":[{"time":"Pending","title":"Pending","detail":"Pending"}],"recordSource":"steps","recordFields":["start","title","detail"]}}"#
  let document = try UIDocument.decode(Data(json.utf8), registeredActions: [])
  let state = DocumentState()
  state.load(document)
  let events = try document.root.resolvedEvents(in: state.records)
  #expect(events.map(\.title) == ["Cook lentils"])
  try state.setRecord("steps", row: "cook", field: "start", to: .text("19:00"))
  #expect(try document.root.resolvedEvents(in: state.records).first?.time == "19:00")
  #expect(throws: UIError.self) { try state.setRecord("steps", row: "cook", field: "title", to: .text("")) }
  #expect(state.records["steps"]?.first?.values["title"] == .text("Cook lentils"))
  #expect(try document.root.resolvedEvents(in: ["steps": []]).isEmpty)
}
