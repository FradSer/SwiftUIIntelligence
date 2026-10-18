import Foundation
import Testing
import SwiftUIIntelligence

@Test func generationRequestIncludesRecordParameterSchemas() throws {
  let request = try DocumentGenerationRequest(messages: [.init(role: .user, content: "Create a shopping list.")],
    calculationSignatures: [.init(id: "shopping", inputs: ["people": .number], outputs: [:],
      recordOutputs: ["ingredients": .init(fields: ["material": .text, "grams": .number])])])
  #expect(request.instructions.contains("ingredients"))
  #expect(request.instructions.contains("material"))
  #expect(request.instructions.contains("grams"))
  #expect(request.instructions.contains("collection IDs"))
}

@Test func legacyScalarSignatureJSONRemainsDecodable() throws {
  let json = #"{"id":"scale","inputs":{"people":"number"},"outputs":{"quantity":"number"}}"#
  let signature = try JSONDecoder().decode(CalculationRegistry.Signature.self, from: Data(json.utf8))
  #expect(signature.recordOutputs.isEmpty)
  let null = json.replacingOccurrences(of: "\"id\":\"scale\"", with: "\"id\":\"scale\",\"recordOutputs\":null")
  #expect(throws: (any Error).self) { try JSONDecoder().decode(CalculationRegistry.Signature.self, from: Data(null.utf8)) }
}

@Test @MainActor func recordAndScalarStateCommitTogether() throws {
  let document = try UIDocument.decode(Data(#"{"version":1,"state":[{"id":"people","kind":"number","value":2},{"id":"summary","kind":"text","value":"Pending"}],"root":{"id":"root","type":"text","text":"Plan"}}"#.utf8), registeredActions: [])
  let registry = try CalculationRegistry([
    .init(id: "shopping", inputs: ["people": .number], outputs: ["summary": .text],
      recordOutputs: ["items": .init(fields: ["amount": .number])]) { values in
      guard case .number(let people) = values["people"] else { throw UIError("Invalid input.") }
      return CalculationResult(values: ["summary": .text("\(Int(people)) portions")], records: ["items": [
        .init(id: "ingredient", values: ["amount": people == 4 ? .text("Invalid") : .number(people * 125)])
      ]])
    }
  ])
  let binding = CalculationBinding(id: "shopping-plan", capability: "shopping", inputs: ["people": "people"],
    outputs: ["summary": "summary"], recordOutputs: ["items": "shopping"])
  let state = DocumentState()
  try state.load(document, calculations: registry, bindings: [binding])
  try state.set("people", to: .number(3))
  #expect(state.records["shopping"]?.first?.values["amount"] == .number(375))
  #expect(state.values["summary"] == .text("3 portions"))
  #expect(throws: UIError.self) { try state.set("people", to: .number(4)) }
  #expect(state.values["people"] == .number(3))
  #expect(state.values["summary"] == .text("3 portions"))
  #expect(state.records["shopping"]?.first?.values["amount"] == .number(375))
}

@Test @MainActor func calculationRecordOutputsRequireDeclaredSchemas() throws {
  let schema = RecordSchema(fields: ["name": .text, "amount": .number])
  let registry = try CalculationRegistry([
    .init(id: "shopping", inputs: ["people": .number], outputs: [:], recordOutputs: ["items": schema]) { inputs in
      guard case .number(let people) = inputs["people"] else { throw UIError("Invalid input.") }
      return CalculationResult(values: [:], records: ["items": [
        .init(id: "lentils", values: ["name": .text("Lentils"), "amount": .number(people * 125)])
      ]])
    }
  ])
  let result = try registry.evaluate("shopping", inputs: ["people": .number(3)])
  #expect(result.records["items"]?.first?.values["amount"] == .number(375))
  #expect(throws: UIError.self) { try registry.calculate("shopping", inputs: ["people": .number(3)]) }
  let invalid = try CalculationRegistry([
    .init(id: "bad", inputs: [:], outputs: [:], recordOutputs: ["items": schema]) { _ in
      CalculationResult(values: [:], records: ["items": [.init(id: "item", values: ["name": .text("Missing amount")])]])
    }
  ])
  #expect(throws: UIError.self) { try invalid.evaluate("bad", inputs: [:]) }
}

@Test func recordDecodingAndBoundsRejectInvalidData() throws {
  let decoder = JSONDecoder()
  let valid = #"{"id":"row","values":{"name":"A"}}"#
  let row = try decoder.decode(RecordRow.self, from: Data(valid.utf8))
  #expect(try decoder.decode(RecordRow.self, from: JSONEncoder().encode(row)) == row)
  for json in [#"{"id":"row","values":{"name":null}}"#,
    #"{"id":"row","values":{"name":[]}}"#,
    #"{"id":"row","values":{},"code":"run"}"#] {
    #expect(throws: (any Error).self) { try decoder.decode(RecordRow.self, from: Data(json.utf8)) }
  }
  let schema = RecordSchema(fields: ["value": .number])
  for number in [Double.nan, Double.infinity, 1_000_000_001] {
    #expect(throws: UIError.self) { try schema.validate([.init(id: "row", values: ["value": .number(number)])]) }
  }
  #expect(throws: UIError.self) {
    try schema.validate((0..<33).map { .init(id: "row-\($0)", values: ["value": .number(1)]) })
  }
  #expect(throws: UIError.self) {
    try RecordSchema(fields: ["name": .text]).validate([.init(id: "row", values: ["name": .text(String(repeating: "x", count: 1001))])])
  }
  #expect(throws: UIError.self) { try RecordSchema(fields: ["bad/path": .text]).validate([]) }
  #expect(throws: UIError.self) {
    try RecordSchema(fields: Dictionary(uniqueKeysWithValues: (0..<17).map { ("field-\($0)", .text) })).validate([])
  }
}

@Test func typedRecordCollectionsValidateEveryRow() throws {
  let schema = RecordSchema(fields: ["name": .text, "amount": .number, "selected": .boolean])
  let rows = [RecordRow(id: "lentils", values: ["name": .text("Lentils"), "amount": .number(375), "selected": .boolean(true)])]
  try schema.validate(rows)
  try schema.validate([])
  for invalid in [
    [RecordRow(id: "lentils", values: ["name": .text("Lentils")])],
    [RecordRow(id: "lentils", values: ["name": .text("Lentils"), "amount": .text("375"), "selected": .boolean(true)])],
    rows + rows,
    [RecordRow(id: "bad/path", values: rows[0].values)],
    [RecordRow(id: "lentils", values: ["name": .text("Lentils"), "amount": .number(.infinity), "selected": .boolean(true)])]
  ] {
    #expect(throws: UIError.self) { try schema.validate(invalid) }
  }
}
