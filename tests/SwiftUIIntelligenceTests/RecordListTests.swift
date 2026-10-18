import Foundation
import Testing
import SwiftUIIntelligence

@Test @MainActor func genericListReadsVariableLengthRecords() throws {
  let json = #"{"version":1,"state":[{"id":"count","kind":"number","value":2}],"calculations":[{"id":"items","capability":"items","inputs":{"count":"count"},"outputs":{},"recordOutputs":{"rows":"items"}}],"root":{"id":"list","type":"list","items":["Pending"],"recordSource":"items","recordFields":["name"]}}"#
  let registry = try CalculationRegistry([
    .init(id: "items", inputs: ["count": .number], outputs: [:], recordOutputs: ["rows": .init(fields: ["name": .text])]) { values in
      guard case .number(let count) = values["count"] else { throw UIError("Invalid count.") }
      return CalculationResult(values: [:], records: ["rows": (0..<Int(count)).map {
        .init(id: "item-\($0)", values: ["name": .text("Item \($0 + 1)")])
      }])
    }
  ])
  let document = try UIDocument.decode(Data(json.utf8), registeredActions: [], registeredCalculations: registry.names)
  let state = DocumentState()
  try state.load(document, calculations: registry)
  #expect(try document.root.resolvedItems(in: state.records) == ["Item 1", "Item 2"])
  try state.set("count", to: .number(0))
  #expect(try document.root.resolvedItems(in: state.records).isEmpty)
}
