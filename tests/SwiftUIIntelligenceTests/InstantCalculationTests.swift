import Foundation
import Testing
@testable import SwiftUIIntelligence
@_spi(Testing) @testable import SwiftUIIntelligenceFoundationModels

@Suite struct InstantCalculationTests {
  private let instant = "2026-10-15T19:00:00Z"

  // Given an instant signature, valid ISO8601 text passes; invalid values fail before the callback.
  @Test @MainActor func registryValidatesInstantInputsAndOutputs() throws {
    var calls = 0
    let registry = try CalculationRegistry([
      .init(id: "echo", inputs: ["when": .instant], outputs: ["result": .instant]) { values in
        calls += 1
        return ["result": values["when"]!]
      },
      .init(id: "invalid", inputs: [:], outputs: ["result": .instant]) { _ in ["result": .text("not-a-date")] },
    ])
    #expect(try registry.calculate("echo", inputs: ["when": .text(instant)]) == ["result": .text(instant)])
    for value in [StateValue.text("not-a-date"), .text("2026-10-15"), .text(String(repeating: "x", count: 4001)), .number(1), .boolean(true)] {
      #expect(throws: UIError.self) { try registry.calculate("echo", inputs: ["when": value]) }
    }
    #expect(calls == 1)
    #expect(throws: UIError.self) { try registry.calculate("invalid", inputs: [:]) }
  }

  // Given a date binding, evaluation works; text and choice bindings fail before the callback.
  @Test @MainActor func bindingRequiresDateFields() throws {
    var calls = 0
    let registry = try CalculationRegistry([
      .init(id: "echo", inputs: ["when": .instant], outputs: ["result": .instant]) { values in
        calls += 1
        return ["result": values["when"]!]
      },
    ])
    for kind in ["date", "text", "choice"] {
      let options = kind == "choice" ? ",\"options\":[\"\(instant)\"]" : ""
      let json = """
        {"version":1,"state":[{"id":"input","kind":"\(kind)","value":"\(instant)"\(options)},{"id":"output","kind":"date","value":"\(instant)"}],"calculations":[{"id":"copy","capability":"echo","inputs":{"when":"input"},"outputs":{"result":"output"}}],"root":{"id":"root","type":"text","text":"Time"}}
        """
      let document = try UIDocument.decode(Data(json.utf8), registeredActions: [], registeredCalculations: ["echo"])
      let state = DocumentState()
      if kind == "date" {
        try state.load(document, calculations: registry)
        #expect(state.values["output"] == .text(instant))
      } else {
        #expect(throws: UIError.self) { try state.load(document, calculations: registry) }
      }
    }
    #expect(calls == 1)
  }

  @Test @MainActor func instantOutputsRejectTextAndChoiceBindingsBeforeExecution() throws {
    var calls = 0
    let registry = try CalculationRegistry([
      .init(id: "time", inputs: [:], outputs: ["result": .instant]) { _ in
        calls += 1
        return ["result": .text(instant)]
      }
    ])
    for kind in ["text", "choice"] {
      let options = kind == "choice" ? ",\"options\":[\"\(instant)\"]" : ""
      let json = """
      {"version":1,"state":[{"id":"output","kind":"\(kind)","value":"\(instant)"\(options)}],"calculations":[{"id":"copy","capability":"time","inputs":{},"outputs":{"result":"output"}}],"root":{"id":"root","type":"text","text":"Time"}}
      """
      let document = try UIDocument.decode(Data(json.utf8), registeredActions: [], registeredCalculations: ["time"])
      #expect(throws: UIError.self) { try DocumentState().load(document, calculations: registry) }
    }
    #expect(calls == 0)
  }

  // Given an instant parameter, only plans that include date state pass.
  @Test func nativePlanRequiresDate() throws {
    let request = try DocumentGenerationRequest(messages: [.init(role: .user, content: "Use the supplied time.")],
      calculationSignatures: [.init(id: "time", inputs: ["when": .instant], outputs: ["result": .text])])
    for instructions in [request.instructions, request.calculationGenerationInstructions, request.calculationDeclarationInstructions] {
      #expect(instructions.contains("when:instant"))
      #expect(instructions.contains("Instant calculation parameters require date state fields with ISO8601 text values."))
    }
    #expect(FoundationModelsDocumentProvider.calculationPlanningInstructions.contains("For every selected instant input or output, include date in stateKinds."))
    #expect(FoundationModelsDocumentProvider.calculationPlanningInstructions.contains("Text calculation values can use text, choice, or date state."))
    for kind in ["date", "text", "choice"] {
      let plan = Data("{\"selectedCapabilityIDs\":[\"time\"],\"componentTypes\":[\"text\"],\"stateKinds\":[\"\(kind)\"]}".utf8)
      if kind == "date" {
        _ = try FoundationModelsDocumentProvider.plannedCalculationSchemaJSON(for: request, plan: plan)
      } else {
        #expect(throws: UIError.self) { try FoundationModelsDocumentProvider.plannedCalculationSchemaJSON(for: request, plan: plan) }
      }
    }
  }

  // Given date and text declarations, instant candidates contain only date IDs; text retains both.
  @Test func nativeBindingCandidatesExcludeTextForInstant() throws {
    let signatures: [CalculationRegistry.Signature] = [.init(id: "time", inputs: ["when": .instant], outputs: ["result": .text])]
    let source = Data("""
      {"state":[{"id":"date-id","kind":"date","value":"\(instant)"},{"id":"text-id","kind":"text","value":"\(instant)"},{"id":"choice-id","kind":"choice","value":"\(instant)","options":["\(instant)"]}],"recordInputs":{"time":{}},"recordOutputs":{"time":{}}}
      """.utf8)
    let accepted = try NativeCalculationData.normalizeData(source, signatures: signatures)
    let schema = try #require(JSONSerialization.jsonObject(with: NativeCalculationData.bindingSchema(data: accepted, signatures: signatures)) as? [String: Any])
    let properties = try #require(schema["properties"] as? [String: [String: Any]])
    let items = try #require(properties["calculations"]?["items"] as? [String: Any])
    let variants = try #require(items["anyOf"] as? [[String: Any]])
    let fields = try #require(variants.first?["properties"] as? [String: [String: Any]])
    let inputs = try #require(fields["inputs"]?["properties"] as? [String: [String: Any]])
    let outputs = try #require(fields["outputs"]?["properties"] as? [String: [String: Any]])
    #expect(inputs["when"]?["enum"] as? [String] == ["date-id"])
    #expect(outputs["result"]?["enum"] as? [String] == ["choice-id", "date-id", "text-id"])
    for id in ["date-id", "text-id", "choice-id"] {
      let bindings = Data("{\"calculations\":[{\"id\":\"copy\",\"capability\":\"time\",\"inputs\":{\"when\":\"\(id)\"},\"outputs\":{\"result\":\"text-id\"},\"recordInputs\":{},\"recordOutputs\":{}}]}".utf8)
      if id == "date-id" {
        _ = try NativeCalculationData.normalizeBindings(bindings, data: accepted, signatures: signatures)
      } else {
        #expect(throws: UIError.self) { try NativeCalculationData.normalizeBindings(bindings, data: accepted, signatures: signatures) }
      }
    }
  }

  // Given an instant record declaration, validation fails even without rows.
  @Test func recordsDoNotAcceptInstantDeclarations() throws {
    #expect(throws: UIError.self) { try RecordSchema(fields: ["when": .instant]).validate([]) }
    let signature = CalculationRegistry.Signature(id: "time", inputs: [:], outputs: ["result": .text], recordInputs: ["rows": .init(fields: ["when": .instant])])
    #expect(throws: UIError.self) {
      try DocumentGenerationRequest(messages: [.init(role: .user, content: "Use the time.")], calculationSignatures: [signature])
    }
    #expect(throws: UIError.self) {
      try NativeCalculationData.dataSchema(from: DocumentGenerationContract.schemaJSON(registeredActions: []), signatures: [signature])
    }
  }
}
