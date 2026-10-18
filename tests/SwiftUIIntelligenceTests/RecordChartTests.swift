import Foundation
import Testing
import SwiftUIIntelligence

@Test func collectionChartRejectsDuplicateCategoriesAndInvalidRadar() throws {
  let json = #"{"id":"chart","type":"chart","title":"Scores","chartStyle":"radar","points":[{"label":"A","value":1,"series":"Score"},{"label":"B","value":2,"series":"Score"},{"label":"C","value":3,"series":"Score"}],"recordSource":"items","recordFields":["name","score","series"]}"#
  let node = try JSONDecoder().decode(UINode.self, from: Data(json.utf8))
  func row(_ id: String, _ name: String, _ score: Double) -> RecordRow {
    .init(id: id, values: ["name": .text(name), "score": .number(score), "series": .text("Score")])
  }
  for rows in [[row("a", "A", 1)], [row("a", "A", 1), row("b", "A", 2), row("c", "C", 3)],
    [row("a", "A", 101), row("b", "B", 2), row("c", "C", 3)]] {
    #expect(throws: UIError.self) { try node.resolvedPoints(values: [:], records: ["items": rows]) }
  }
  #expect(try node.resolvedPoints(values: [:], records: ["items": []]).isEmpty)
}

@Test @MainActor func chartProjectsVariableRecordCategoriesAndRejectsInvalidSeries() throws {
  let json = #"{"version":1,"state":[{"id":"count","kind":"number","value":2}],"calculations":[{"id":"compare","capability":"compare","inputs":{"count":"count"},"outputs":{},"recordOutputs":{"items":"items"}}],"root":{"id":"chart","type":"chart","title":"Prices","chartStyle":"bar","points":[{"label":"Pending","value":1,"series":"Price"}],"recordSource":"items","recordFields":["name","price","series"]}}"#
  let registry = try CalculationRegistry([
    .init(id: "compare", inputs: ["count": .number], outputs: [:],
      recordOutputs: ["items": .init(fields: ["name": .text, "price": .number, "series": .text])]) { values in
      guard case .number(let count) = values["count"] else { throw UIError("Invalid count.") }
      return CalculationResult(values: [:], records: ["items": (0..<Int(count)).map {
        .init(id: "product-\($0)", values: ["name": .text("Product \($0 + 1)"), "price": .number(Double(($0 + 1) * 25)), "series": .text("Price")])
      }])
    }
  ])
  let document = try UIDocument.decode(Data(json.utf8), registeredActions: [], registeredCalculations: registry.names)
  let state = DocumentState()
  try state.load(document, calculations: registry)
  #expect(try document.root.resolvedPoints(values: state.values, records: state.records).map(\.value) == [25, 50])
  try state.set("count", to: .number(1))
  #expect(try document.root.resolvedPoints(values: state.values, records: state.records).map(\.label) == ["Product 1"])
  try state.set("count", to: .number(0))
  #expect(try document.root.resolvedPoints(values: state.values, records: state.records).isEmpty)
}
