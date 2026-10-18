import Foundation
import Testing
import SwiftUIIntelligence

@Test @MainActor func sessionRetainsItsCalculationRegistryIdentity() throws {
  let registry = try CalculationRegistry([
    .init(id: "double", inputs: ["input": .number], outputs: ["output": .number]) { values in
      guard case .number(let input) = values["input"] else { throw UIError("Invalid input.") }
      return ["output": .number(input * 2)]
    }
  ])
  let session = DocumentChatSession(provider: ChatResponseProvider { _ in "{}" }, calculations: registry)
  #expect(session.calculationRegistry?.revision == registry.revision)
  #expect(try session.calculationRegistry?.calculate("double", inputs: ["input": .number(3)]) == ["output": .number(6)])
}

private let calculatedDocumentJSON = #"{"version":1,"state":[{"id":"people","kind":"number","value":2},{"id":"quantity","kind":"number","value":0}],"calculations":[{"id":"scale-ingredients","capability":"scale","inputs":{"people":"people"},"outputs":{"quantity":"quantity"}}],"root":{"id":"root","type":"text","text":"Plan"}}"#

private struct CalculatedDocumentProvider: DocumentGenerationProvider {
  func generate(_ request: DocumentGenerationRequest) async throws -> Data {
    guard request.registeredCalculations == ["scale"] else { throw UIError("Missing calculation authorization.") }
    return Data(calculatedDocumentJSON.utf8)
  }
}

@Test @MainActor func generationSessionValidatesCalculationsBeforeCommit() async throws {
  let valid = try CalculationRegistry([
    .init(id: "scale", inputs: ["people": .number], outputs: ["quantity": .number]) { input in
      guard case .number(let people) = input["people"] else { throw UIError("Invalid input.") }
      return ["quantity": .number(people * 2)]
    }
  ])
  let session = DocumentChatSession(provider: CalculatedDocumentProvider(), calculations: valid)
  await session.send("Scale the supplied amount.")
  #expect(session.phase == .ready)
  #expect(session.document?.calculations.count == 1)
  let invalid = try CalculationRegistry([
    .init(id: "scale", inputs: ["wrong": .number], outputs: ["quantity": .number]) { _ in
      Issue.record("An incompatible binding must not execute.")
      return ["quantity": .number(1)]
    }
  ])
  let rejected = DocumentChatSession(provider: CalculatedDocumentProvider(), calculations: invalid)
  await rejected.send("Scale the supplied amount.")
  #expect(rejected.phase == .failed)
  #expect(rejected.failureKind == .invalidDocument)
  #expect(rejected.document == nil && rejected.revision == 0)
}

@Test func calculationRequestIncludesHostParameterSignatures() throws {
  let request = try DocumentGenerationRequest(messages: [.init(role: .user, content: "Scale")],
    calculationSignatures: [.init(id: "scale", inputs: ["people": .number], outputs: ["quantity": .number])])
  #expect(request.registeredCalculations == ["scale"])
  #expect(request.instructions.contains("people"))
  #expect(request.instructions.contains("quantity"))
}

@Test func textOutputBindingsRequireDeclaredTextFields() throws {
  let json = #"{"version":1,"state":[{"id":"answer","kind":"text","value":"Ready"}],"root":{"id":"result","type":"text","text":"Pending","binding":"answer"}}"#
  let document = try UIDocument.decode(Data(json.utf8), registeredActions: [])
  #expect(document.root.binding == "answer")
  let encoded = try DocumentGenerationContract.canonicalJSON(document)
  #expect(try UIDocument.decode(encoded, registeredActions: []).root.binding == "answer")
  for invalid in [json.replacingOccurrences(of: "\"binding\":\"answer\"", with: "\"binding\":\"unknown\""),
    json.replacingOccurrences(of: "\"kind\":\"text\",\"value\":\"Ready\"", with: "\"kind\":\"number\",\"value\":1")] {
    #expect(throws: UIError.self) { try UIDocument.decode(Data(invalid.utf8), registeredActions: []) }
  }
}

@Test func calculationSchemaExposesOnlyRegisteredCapabilities() throws {
  let data = DocumentGenerationContract.schemaJSON(registeredActions: [], registeredCalculations: ["scale"])
  let schema = try JSONSerialization.jsonObject(with: data) as! [String: Any]
  let properties = schema["properties"] as! [String: Any]
  let calculations = properties["calculations"] as! [String: Any]
  let item = calculations["items"] as! [String: Any]
  let fields = item["properties"] as! [String: Any]
  let capability = fields["capability"] as! [String: Any]
  #expect(capability["enum"] as? [String] == ["scale"])
}

@Test func generatedCalculationBindingsRequireHostAuthorization() throws {
  let data = Data(calculatedDocumentJSON.utf8)
  #expect(throws: UIError.self) { try UIDocument.decode(data, registeredActions: []) }
  let document = try UIDocument.decode(data, registeredActions: [], registeredCalculations: ["scale"])
  #expect(document.calculations.count == 1)
  let encoded = try DocumentGenerationContract.canonicalJSON(document)
  let again = try UIDocument.decode(encoded, registeredActions: [], registeredCalculations: ["scale"])
  #expect(again.calculations.first?.capability == "scale")
  let legacy = try UIDocument.decode(Data(#"{"version":1,"root":{"id":"root","type":"text","text":"Old document"}}"#.utf8), registeredActions: [])
  #expect(legacy.calculations.isEmpty)
  #expect(!String(decoding: try DocumentGenerationContract.canonicalJSON(legacy), as: UTF8.self).contains("calculations"))
}

@Test @MainActor func reactiveDocumentLoadRequiresItsCalculationRegistry() throws {
  let document = try UIDocument.decode(Data(calculatedDocumentJSON.utf8), registeredActions: [], registeredCalculations: ["scale"])
  let registry = try CalculationRegistry([
    .init(id: "scale", inputs: ["people": .number], outputs: ["quantity": .number]) { input in
      guard case .number(let people) = input["people"] else { throw UIError("Invalid input.") }
      return ["quantity": .number(people * 2)]
    }
  ])
  let state = DocumentState()
  try state.load(document, calculations: registry)
  #expect(state.values["quantity"] == .number(4))
  state.load(document)
  #expect(state.errorMessage != nil)
  try state.set("people", to: .number(3))
  #expect(state.values["quantity"] == .number(6))
}

@Test func generatedCalculationBindingsRejectCyclesAndDerivedControls() {
  let cycle = calculatedDocumentJSON.replacingOccurrences(of: "\"people\":\"people\"", with: "\"people\":\"quantity\"")
  let unknown = calculatedDocumentJSON.replacingOccurrences(of: "\"quantity\":\"quantity\"", with: "\"quantity\":\"missing\"")
  let control = calculatedDocumentJSON.replacingOccurrences(of: "\"type\":\"text\",\"text\":\"Plan\"", with: "\"type\":\"control\",\"title\":\"Quantity\",\"binding\":\"quantity\",\"controlType\":\"stepper\"")
  let null = #"{"version":1,"calculations":null,"root":{"id":"root","type":"text","text":"Plan"}}"#
  let duplicateOwner = calculatedDocumentJSON.replacingOccurrences(of: "\"quantity\":\"quantity\"", with: "\"quantity\":\"quantity\",\"alias\":\"quantity\"")
  for json in [cycle, unknown, control, null, duplicateOwner] {
    #expect(throws: UIError.self) {
      try UIDocument.decode(Data(json.utf8), registeredActions: [], registeredCalculations: ["scale"])
    }
  }
}

@Test func calculationBindingJSONRejectsUnknownAndMissingFields() throws {
  let json = #"{"id":"scale","capability":"multiply","inputs":{"people":"people"},"outputs":{"amount":"amount"}}"#
  let binding = try JSONDecoder().decode(CalculationBinding.self, from: Data(json.utf8))
  #expect(binding.inputs == ["people": "people"])
  let roundTrip = try JSONDecoder().decode(CalculationBinding.self, from: JSONEncoder().encode(binding))
  #expect(roundTrip.capability == "multiply")
  for invalid in [json.replacingOccurrences(of: "\"id\":\"scale\",", with: ""),
    json.replacingOccurrences(of: "\"id\":\"scale\"", with: "\"id\":\"scale\",\"code\":\"run\"")] {
    #expect(throws: (any Error).self) { try JSONDecoder().decode(CalculationBinding.self, from: Data(invalid.utf8)) }
  }
}

@Test @MainActor func calculatedStateEditsUpdateDependentValuesAtomically() throws {
  let document = try UIDocument.decode(Data(#"{"version":1,"state":[{"id":"people","kind":"number","value":2,"minimum":1,"maximum":20},{"id":"quantity","kind":"number","value":0,"minimum":0,"maximum":1000}],"root":{"id":"root","type":"text","text":"Plan"}}"#.utf8), registeredActions: [])
  let registry = try CalculationRegistry([
    .init(id: "scale", inputs: ["people": .number], outputs: ["quantity": .number]) { inputs in
      guard case .number(let people) = inputs["people"] else { throw UIError("Invalid input.") }
      return ["quantity": .number(people * 125)]
    }
  ])
  let state = DocumentState()
  try state.load(document, calculations: registry, bindings: [
    .init(id: "ingredients", capability: "scale", inputs: ["people": "people"], outputs: ["quantity": "quantity"])
  ])
  #expect(state.values["quantity"] == .number(250))
  try state.set("people", to: .number(3))
  #expect(state.values["quantity"] == .number(375))
  #expect(throws: UIError.self) { try state.set("people", to: .number(9)) }
  #expect(state.values["people"] == .number(3))
  #expect(state.values["quantity"] == .number(375))
  #expect(throws: UIError.self) { try state.set("quantity", to: .number(1)) }
  #expect(state.values["quantity"] == .number(375))
}

@Test @MainActor func laterCalculationFailureRetainsValuesAndPreviousPlan() throws {
  let document = try UIDocument.decode(Data(#"{"version":1,"state":[{"id":"a","kind":"number","value":1},{"id":"b","kind":"number","value":0},{"id":"c","kind":"number","value":0}],"root":{"id":"root","type":"text","text":"Values"}}"#.utf8), registeredActions: [])
  let registry = try CalculationRegistry([
    .init(id: "double", inputs: ["input": .number], outputs: ["output": .number]) { input in
      guard case .number(let number) = input["input"] else { throw UIError("Invalid input.") }
      return ["output": .number(number * 2)]
    },
    .init(id: "bounded", inputs: ["input": .number], outputs: ["output": .number]) { input in
      guard case .number(let number) = input["input"], number <= 8 else { throw UIError("Calculation limit exceeded.") }
      return ["output": .number(number + 1)]
    }
  ])
  let bindings: [CalculationBinding] = [
    .init(id: "first", capability: "double", inputs: ["input": "a"], outputs: ["output": "b"]),
    .init(id: "second", capability: "bounded", inputs: ["input": "b"], outputs: ["output": "c"])
  ]
  let state = DocumentState()
  try state.load(document, calculations: registry, bindings: bindings)
  try state.set("a", to: .number(3))
  #expect(throws: UIError.self) { try state.set("a", to: .number(5)) }
  #expect(state.values == ["a": .number(3), "b": .number(6), "c": .number(7)])
  let invalid = [CalculationBinding(id: "invalid", capability: "missing", inputs: [:], outputs: ["output": "c"])]
  #expect(throws: UIError.self) { try state.load(document, calculations: registry, bindings: invalid) }
  try state.set("a", to: .number(4))
  #expect(state.values == ["a": .number(4), "b": .number(8), "c": .number(9)])
  try state.load(document, calculations: registry, bindings: bindings)
  #expect(state.values["a"] == .number(4))
  #expect(state.values["c"] == .number(9))
  try state.load(document, calculations: registry, bindings: bindings, preservingEdits: false)
  #expect(state.values == ["a": .number(1), "b": .number(2), "c": .number(3)])
}

@Test @MainActor func dependentCalculationsResolveOrderAndRejectCyclesBeforeExecution() throws {
  let document = try UIDocument.decode(Data(#"{"version":1,"state":[{"id":"a","kind":"number","value":1},{"id":"b","kind":"number","value":0},{"id":"c","kind":"number","value":0}],"root":{"id":"root","type":"text","text":"Values"}}"#.utf8), registeredActions: [])
  var calls = 0
  let registry = try CalculationRegistry([
    .init(id: "double", inputs: ["input": .number], outputs: ["output": .number]) { inputs in
      calls += 1
      guard case .number(let number) = inputs["input"] else { throw UIError("Invalid input.") }
      return ["output": .number(number * 2)]
    }
  ])
  let first = CalculationBinding(id: "first", capability: "double", inputs: ["input": "a"], outputs: ["output": "b"])
  let second = CalculationBinding(id: "second", capability: "double", inputs: ["input": "b"], outputs: ["output": "c"])
  let state = DocumentState()
  try state.load(document, calculations: registry, bindings: [second, first])
  try state.set("a", to: .number(3))
  #expect(state.values == ["a": .number(3), "b": .number(6), "c": .number(12)])
  let previous = state.values
  calls = 0
  let cycle = CalculationBinding(id: "cycle", capability: "double", inputs: ["input": "c"], outputs: ["output": "a"])
  #expect(throws: UIError.self) { try state.load(document, calculations: registry, bindings: [first, second, cycle]) }
  #expect(calls == 0)
  #expect(state.values == previous)
  #expect(throws: UIError.self) { try state.load(document, calculations: registry, bindings: [first, first]) }
  #expect(calls == 0)
}

@Test @MainActor func registeredCalculationReturnsTypedOutputs() throws {
  let registry = try CalculationRegistry([
    .init(id: "scale", inputs: ["quantity": .number, "people": .number], outputs: ["amount": .number]) { inputs in
      guard case .number(let quantity) = inputs["quantity"],
        case .number(let people) = inputs["people"] else { throw UIError("Invalid input.") }
      return ["amount": .number(quantity * people)]
    }
  ])
  let result = try registry.calculate("scale", inputs: ["quantity": .number(125), "people": .number(3)])
  #expect(result == ["amount": .number(375)])
}

@Test @MainActor func invalidCalculationInputsNeverInvokeHost() throws {
  var invocations = 0
  let registry = try CalculationRegistry([
    .init(id: "local", inputs: ["value": .number], outputs: ["result": .number]) { _ in
      invocations += 1
      return ["result": .number(1)]
    }
  ])
  for inputs: [String: StateValue] in [[:], ["value": .text("1")], ["value": .number(.infinity)],
    ["value": .number(1), "extra": .boolean(true)]] {
    #expect(throws: UIError.self) { try registry.calculate("local", inputs: inputs) }
  }
  #expect(throws: UIError.self) { try registry.calculate("unknown", inputs: ["value": .number(1)]) }
  #expect(invocations == 0)
}

@Test @MainActor func invalidCalculationResultsAreRejected() throws {
  for outputs: [String: StateValue] in [[:], ["value": .text("wrong")], ["value": .number(.nan)],
    ["value": .number(1), "extra": .boolean(false)]] {
    let registry = try CalculationRegistry([
      .init(id: "local", inputs: [:], outputs: ["value": .number]) { _ in outputs }
    ])
    #expect(throws: UIError.self) { try registry.calculate("local", inputs: [:]) }
  }
}

@Test @MainActor func calculationTextBoundsAndHostErrorsRemainExplicit() throws {
  let registry = try CalculationRegistry([
    .init(id: "echo", inputs: ["text": .text, "enabled": .boolean], outputs: ["text": .text, "enabled": .boolean]) { $0 },
    .init(id: "long", inputs: [:], outputs: ["text": .text]) { _ in ["text": .text(String(repeating: "x", count: 4001))] },
    .init(id: "failure", inputs: [:], outputs: ["text": .text]) { _ in throw UIError("Host calculation failed.") }
  ])
  let valid: [String: StateValue] = ["text": .text(String(repeating: "x", count: 4000)), "enabled": .boolean(true)]
  #expect(try registry.calculate("echo", inputs: valid) == valid)
  #expect(throws: UIError.self) {
    try registry.calculate("echo", inputs: ["text": .text(String(repeating: "x", count: 4001)), "enabled": .boolean(true)])
  }
  #expect(throws: UIError.self) { try registry.calculate("long", inputs: [:]) }
  do {
    _ = try registry.calculate("failure", inputs: [:])
    Issue.record("Expected the host error.")
  } catch {
    #expect(error.localizedDescription == "Host calculation failed.")
  }
}

@Test @MainActor func ambiguousCalculationSignaturesAreRejected() {
  let duplicate = CalculationRegistry.Capability(id: "local", inputs: [:], outputs: ["value": .number]) { _ in
    ["value": .number(1)]
  }
  #expect(throws: UIError.self) { try CalculationRegistry([duplicate, duplicate]) }
  let invalid = CalculationRegistry.Capability(id: "https://example.com", inputs: [:], outputs: [:]) { _ in [:] }
  #expect(throws: UIError.self) { try CalculationRegistry([invalid]) }
}
