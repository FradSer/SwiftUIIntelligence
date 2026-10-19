import Foundation
import Testing
import SwiftUIIntelligence

@Test func signatureMetadataRejectsWrongDerivedProjectionBeforeCalculation() throws {
  let json = #"{"version":1,"calculations":[{"id":"plan","capability":"plan","inputs":{},"outputs":{},"recordOutputs":{"rows":"derived"}}],"root":{"id":"table","type":"table","columns":["Name"],"rows":[["Pending"]],"recordSource":"derived","recordFields":["missing"]}}"#
  let document = try UIDocument.decode(Data(json.utf8), registeredActions: [], registeredCalculations: ["plan"])
  let signatures: [CalculationRegistry.Signature] = [.init(id: "plan", inputs: [:], outputs: [:], recordOutputs: ["rows": .init(fields: ["name": .text])])]
  #expect(throws: UIError.self) { try document.validateRecordFields(signatures: signatures) }
}

@Test func tableProjectionDereferencesTargetEntityIDsToHumanNames() throws {
  let json = #"{"id":"table","type":"table","columns":["Person"],"rows":[["Pending"]],"recordSource":"assignments","recordFields":["personID"]}"#
  let node = try JSONDecoder().decode(UINode.self, from: Data(json.utf8))
  let rows = try node.resolvedRows(in: [
    "people": [.init(id: "p-ada", values: ["name": .text("Ada")])],
    "assignments": [.init(id: "a-1", values: ["personID": .text("p-ada")])]
  ])
  #expect(rows == [["Ada"]])
}

@Test func tableProjectionPreservesFractionalNumericFacts() throws {
  let json = #"{"id":"table","type":"table","columns":["Amount"],"rows":[["Pending"]],"recordSource":"items","recordFields":["amount"]}"#
  let node = try JSONDecoder().decode(UINode.self, from: Data(json.utf8))
  let rows = try node.resolvedRows(in: ["items": [
    .init(id: "fraction", values: ["amount": .number(1.23456)]),
    .init(id: "small", values: ["amount": .number(0.0001)]),
    .init(id: "precise", values: ["amount": .number(1.2345678901234567)])
  ]])
  #expect(rows == [["1.23456"], ["0.0001"], ["1.2345678901234567"]])
}

@Test @MainActor func unknownProjectionFieldsRejectBeforeEmptyCollectionCalculation() throws {
  let json = #"{"version":1,"calculations":[{"id":"items","capability":"items","inputs":{},"outputs":{},"recordOutputs":{"rows":"items"}}],"root":{"id":"table","type":"table","columns":["Name"],"rows":[["Pending"]],"recordSource":"items","recordFields":["missing"]}}"#
  var calls = 0
  let registry = try CalculationRegistry([
    .init(id: "items", inputs: [:], outputs: [:], recordOutputs: ["rows": .init(fields: ["name": .text])]) { _ in
      calls += 1
      return CalculationResult(values: [:], records: ["rows": []])
    }
  ])
  let document = try UIDocument.decode(Data(json.utf8), registeredActions: [], registeredCalculations: registry.names)
  let state = DocumentState()
  #expect(throws: UIError.self) { try state.load(document, calculations: registry) }
  #expect(calls == 0)
  #expect(state.values.isEmpty && state.records.isEmpty)
}

@Test func duplicateRecordOwnersRejectDuringDocumentDecode() {
  let prefix = #"{"version":1,"calculations": ["#
  let suffix = #"],"root":{"id":"root","type":"text","text":"Plan"}}"#
  let first = #"{"id":"one","capability":"shopping","inputs":{},"outputs":{},"recordOutputs":{"items":"shared"}}"#
  let second = first.replacingOccurrences(of: "\"id\":\"one\"", with: "\"id\":\"two\"")
  let alias = first.replacingOccurrences(of: "\"items\":\"shared\"", with: "\"items\":\"shared\",\"other\":\"shared\"")
  for bindings in [first + "," + second, alias] {
    #expect(throws: UIError.self) {
      try UIDocument.decode(Data((prefix + bindings + suffix).utf8), registeredActions: [], registeredCalculations: ["shopping"])
    }
  }
}

@Test @MainActor func genericTableProjectsCalculatedRowsAndEmptyResults() throws {
  let json = #"{"version":1,"state":[{"id":"people","kind":"number","value":2}],"calculations":[{"id":"shopping","capability":"shopping","inputs":{"people":"people"},"outputs":{},"recordOutputs":{"items":"shopping"}}],"root":{"id":"table","type":"table","columns":["Ingredient","Amount"],"rows":[["Pending","Pending"]],"recordSource":"shopping","recordFields":["name","amount"]}}"#
  let registry = try CalculationRegistry([
    .init(id: "shopping", inputs: ["people": .number], outputs: [:],
      recordOutputs: ["items": .init(fields: ["name": .text, "amount": .number])]) { values in
      guard case .number(let people) = values["people"] else { throw UIError("Invalid people.") }
      return CalculationResult(values: [:], records: ["items": people == 0 ? [] : [
        .init(id: "ingredient", values: ["name": .text("Lentils"), "amount": .number(people * 125)])
      ]])
    }
  ])
  let document = try UIDocument.decode(Data(json.utf8), registeredActions: [], registeredCalculations: registry.names)
  let state = DocumentState()
  try state.load(document, calculations: registry)
  #expect(try document.root.resolvedRows(in: state.records) == [["Lentils", "250"]])
  try state.set("people", to: .number(3))
  #expect(try document.root.resolvedRows(in: state.records) == [["Lentils", "375"]])
  try state.set("people", to: .number(0))
  #expect(try document.root.resolvedRows(in: state.records).isEmpty)
}
