import Foundation
import Testing
import SwiftUIIntelligence

@Test @MainActor func sourceAndDerivedCollectionsShareOneLimitBeforeCallbacks() throws {
  let schema = RecordSchema(fields: ["name": .text])
  var calls = 0
  let registry = try CalculationRegistry([
    .init(id: "rows", inputs: [:], outputs: [:], recordOutputs: ["rows": schema]) { _ in
      calls += 1
      return CalculationResult(values: [:], records: ["rows": []])
    }
  ])
  for (sources, derived) in [(0, 17), (8, 9)] {
    let declarations = (0..<sources).map { index in
      "{\"id\":\"source-\(index)\",\"schema\":{\"fields\":{\"name\":\"text\"}},\"rows\":[]}"
    }.joined(separator: ",")
    let json = "{\"version\":1,\"records\":[\(declarations)],\"root\":{\"id\":\"root\",\"type\":\"text\",\"text\":\"Rows\"}}"
    let document = try UIDocument.decode(Data(json.utf8), registeredActions: [])
    let bindings = (0..<derived).map { index in
      CalculationBinding(id: "binding-\(index)", capability: "rows", inputs: [:], outputs: [:], recordOutputs: ["rows": "derived-\(index)"])
    }
    let state = DocumentState()
    #expect(throws: UIError.self) { try state.load(document, calculations: registry, bindings: bindings) }
    #expect(calls == 0)
    #expect(state.records.isEmpty)
  }
}

@Test func generationRequestAdvertisesDeclaredRecordInputs() throws {
  let request = try DocumentGenerationRequest(messages: [.init(role: .user, content: "Edit the supplied bill.")],
    calculationSignatures: [.init(id: "total", inputs: [:], outputs: ["total": .number],
      recordInputs: ["billItems": .init(fields: ["amountMinor": .number, "included": .boolean])])])
  #expect(request.instructions.contains("billItems"))
  #expect(request.instructions.contains("amountMinor"))
  let object = try JSONSerialization.jsonObject(with: request.schemaJSON) as! [String: Any]
  let properties = object["properties"] as! [String: Any]
  #expect(properties["records"] != nil)
}

@Test @MainActor func recordCellEditsRecalculateBeforeAtomicCommit() throws {
  let json = #"{"version":1,"state":[{"id":"total","kind":"number","value":0,"maximum":10000}],"records":[{"id":"items","schema":{"fields":{"amount":"number"}},"rows":[{"id":"tea","values":{"amount":125}}]}],"calculations":[{"id":"total","capability":"total","inputs":{},"outputs":{"total":"total"},"recordInputs":{"items":"items"}}],"root":{"id":"root","type":"text","text":"Bill"}}"#
  let registry = try CalculationRegistry([
    .init(id: "total", inputs: [:], outputs: ["total": .number], recordInputs: ["items": .init(fields: ["amount": .number])], recordOutputs: [:]) { _, records in
      guard let items = records["items"] else { throw UIError("Missing items.") }
      var total = 0.0
      for item in items {
        guard case .number(let amount) = item.values["amount"], amount >= 0 else { throw UIError("Negative amount.") }
        total += amount
      }
      return CalculationResult(values: ["total": .number(total)])
    }
  ])
  let document = try UIDocument.decode(Data(json.utf8), registeredActions: [], registeredCalculations: registry.names)
  let state = DocumentState()
  try state.load(document, calculations: registry)
  try state.setRecord("items", row: "tea", field: "amount", to: .number(150))
  #expect(state.values["total"] == .number(150))
  #expect(throws: UIError.self) { try state.setRecord("items", row: "tea", field: "amount", to: .number(-1)) }
  #expect(state.values["total"] == .number(150))
  #expect(state.records["items"]?.first?.values["amount"] == .number(150))
}

@Test func editableTableFieldsRequireSourceRecordDeclarations() throws {
  let json = #"{"version":1,"records":[{"id":"items","schema":{"fields":{"name":"text","amount":"number","included":"boolean"}},"rows":[{"id":"tea","values":{"name":"Tea","amount":125,"included":true}}]}],"root":{"id":"table","type":"table","columns":["Name","Amount","Included"],"rows":[["Pending","Pending","Pending"]],"recordSource":"items","recordFields":["name","amount","included"],"editableFields":["amount","included"]}}"#
  let document = try UIDocument.decode(Data(json.utf8), registeredActions: [])
  #expect(document.root.editableFields == ["amount", "included"])
  #expect(throws: UIError.self) {
    try UIDocument.decode(Data(json.replacingOccurrences(of: "\"editableFields\":[\"amount\",\"included\"]", with: "\"editableFields\":[\"missing\"]").utf8), registeredActions: [])
  }
}

@Test @MainActor func declaredRecordCollectionsRenderWithoutCalculationOwners() throws {
  let json = #"{"version":1,"records":[{"id":"items","schema":{"fields":{"name":"text","amount":"number"}},"rows":[{"id":"tea","values":{"name":"Tea","amount":125}}]}],"root":{"id":"table","type":"table","columns":["Name","Amount"],"rows":[["Pending","Pending"]],"recordSource":"items","recordFields":["name","amount"]}}"#
  let document = try UIDocument.decode(Data(json.utf8), registeredActions: [])
  let state = DocumentState()
  state.load(document)
  #expect(state.errorMessage == nil)
  #expect(try document.root.resolvedRows(in: state.records) == [["Tea", "125"]])
  try state.setRecord("items", row: "tea", field: "amount", to: .number(150))
  #expect(try document.root.resolvedRows(in: state.records) == [["Tea", "150"]])
}

@Test @MainActor func declaredRecordCellsValidateEditsAndPreserveStableRows() throws {
  let json = #"{"version":1,"records":[{"id":"items","schema":{"fields":{"name":"text","amount":"number","included":"boolean"}},"rows":[{"id":"tea","values":{"name":"Tea","amount":125,"included":true}}]}],"root":{"id":"root","type":"text","text":"Items"}}"#
  let document = try UIDocument.decode(Data(json.utf8), registeredActions: [])
  let state = DocumentState()
  state.load(document)
  try state.setRecord("items", row: "tea", field: "amount", to: .number(150))
  #expect(state.records["items"]?.first?.values["amount"] == .number(150))
  #expect(throws: UIError.self) { try state.setRecord("items", row: "tea", field: "amount", to: .text("150")) }
  #expect(throws: UIError.self) { try state.setRecord("items", row: "missing", field: "amount", to: .number(1)) }
  state.load(document)
  #expect(state.records["items"]?.first?.values["amount"] == .number(150))
  state.load(document, preservingEdits: false)
  #expect(state.records["items"]?.first?.values["amount"] == .number(125))
}
