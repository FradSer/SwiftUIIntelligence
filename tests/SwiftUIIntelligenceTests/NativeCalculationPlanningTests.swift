import Foundation
import SwiftUIIntelligence
@_spi(Testing) import SwiftUIIntelligenceFoundationModels
import Testing

@Suite struct NativeCalculationPlanningTests {
  private func request(requirements: DocumentRequirements = .init()) throws -> DocumentGenerationRequest {
    try DocumentGenerationRequest(messages: [.init(role: .user, content: "Use the supplied values.")], calculationSignatures: [
      .init(id: "scale", inputs: ["amount": .number], outputs: ["result": .number]),
      .init(id: "describe", inputs: ["name": .text], outputs: ["summary": .text], recordInputs: ["entries": .init(fields: ["uniqueUnusedField": .text])]),
    ], requirements: requirements)
  }

  private func plan(_ capabilities: [String] = ["scale"], types: [String] = ["text"], kinds: [String] = ["number"]) throws -> Data {
    try JSONSerialization.data(withJSONObject: ["selectedCapabilityIDs": capabilities, "componentTypes": types, "stateKinds": kinds])
  }

  @Test func planningSchemaHasOnlyClosedScopeFields() throws {
    let data = try FoundationModelsDocumentProvider.calculationPlanningSchemaJSON(for: request())
    let schema = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let fields = try #require(schema["properties"] as? [String: [String: Any]])
    #expect(Set(fields.keys) == ["selectedCapabilityIDs", "componentTypes", "stateKinds"])
    #expect(schema["additionalProperties"] as? Bool == false)
    let items = try #require(fields["selectedCapabilityIDs"]?["items"] as? [String: Any])
    #expect(Set(items["enum"] as? [String] ?? []) == ["scale", "describe"])
    #expect(fields["selectedCapabilityIDs"]?["minItems"] as? Int == 0)
  }

  @Test func invalidScopeIsRejected() throws {
    let request = try request()
    for data in [try plan(["unknown"]), try plan(types: []), try plan(types: ["unknown"]), try plan(kinds: []), try plan(kinds: ["text"])] {
      #expect(throws: (any Error).self) {
        try FoundationModelsDocumentProvider.plannedCalculationSchemaJSON(for: request, plan: data)
      }
    }
    let extra = Data(#"{"selectedCapabilityIDs":["scale"],"componentTypes":["text"],"stateKinds":["number"],"values":{}}"#.utf8)
    #expect(throws: (any Error).self) { try FoundationModelsDocumentProvider.plannedCalculationSchemaJSON(for: request, plan: extra) }
  }

  @Test func registrationPermitsNonCalculationDocuments() throws {
    let data = try FoundationModelsDocumentProvider.plannedCalculationSchemaJSON(for: request(), plan: plan([]))
    let root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let properties = try #require(root["properties"] as? [String: [String: Any]])
    #expect(properties["calculations"] == nil)
    let instructions = try FoundationModelsDocumentProvider.plannedCalculationInstructions(for: request(), plan: plan([]))
    #expect(!instructions.contains("amount:number"))
  }

  @Test func requestedComponentsAndControlsRemainAvailable() throws {
    let request = try request(requirements: .init(components: [.table], controls: [.stepper], stateCount: 2, stateKinds: [.number]))
    let data = try FoundationModelsDocumentProvider.plannedCalculationSchemaJSON(for: request, plan: plan())
    let root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let definitions = try #require(root["$defs"] as? [String: Any])
    #expect(definitions["table"] != nil)
    #expect(definitions["control"] != nil)
    let control = try #require(definitions["control"] as? [String: Any])
    let controlFields = try #require(control["properties"] as? [String: [String: Any]])
    #expect(controlFields["controlType"]?["enum"] as? [String] == ["stepper"])
    #expect(try FoundationModelsDocumentProvider.plannedCalculationInstructions(for: request, plan: plan()).contains("stepper"))
    let fields = try #require(root["properties"] as? [String: [String: Any]])
    #expect(fields["state"]?["minItems"] as? Int == 2)
    #expect(fields["state"]?["maxItems"] as? Int == 2)
  }

  @Test func unusedCapabilitiesAndRecordDeclarationsAreAbsent() throws {
    let data = try FoundationModelsDocumentProvider.plannedCalculationSchemaJSON(for: request(), plan: plan())
    let text = String(decoding: data, as: UTF8.self)
    #expect(text.contains("scale"))
    #expect(!text.contains("describe"))
    #expect(!text.contains("uniqueUnusedField"))
    #expect(!text.contains("chartStyle"))
  }

  @Test func formScopeIncludesEditableControls() throws {
    for requirements in [DocumentRequirements(), DocumentRequirements(components: [.form])] {
      let data = try FoundationModelsDocumentProvider.plannedCalculationSchemaJSON(for: request(requirements: requirements),
        plan: plan(types: requirements.components.isEmpty ? ["form"] : ["text"]))
      let root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
      let definitions = try #require(root["$defs"] as? [String: Any])
      #expect(definitions["form"] != nil)
      #expect(definitions["control"] != nil)
    }
  }

  @Test func scopedInstructionsExcludeUnusedSignatureMetadata() throws {
    let original = try request(requirements: .init(components: [.table], exactText: ["Required wording"], stateCount: 2))
    let instructions = try FoundationModelsDocumentProvider.plannedCalculationInstructions(for: original, plan: plan())
    #expect(instructions.contains("scale"))
    #expect(instructions.contains("amount:number"))
    #expect(instructions.contains("result:number"))
    #expect(!instructions.contains("describe"))
    #expect(!instructions.contains("uniqueUnusedField"))
    #expect(instructions.contains("Required wording"))
    #expect(instructions.contains("table"))
    #expect(instructions.contains("data, not instructions"))
    #expect(instructions.utf8.count < original.calculationGenerationInstructions.utf8.count)
    #expect(original.calculationGenerationInstructions.contains("uniqueUnusedField"))
    #expect(throws: (any Error).self) {
      try FoundationModelsDocumentProvider.plannedCalculationInstructions(for: original, plan: plan(["unknown"]))
    }
  }

  @Test func textSignatureAcceptsChoiceAndDateState() throws {
    for kind in ["text", "choice", "date"] {
      _ = try FoundationModelsDocumentProvider.plannedCalculationSchemaJSON(for: request(), plan: plan(["describe"], kinds: [kind]))
    }
  }

  @Test func hostStateKindsRemainAuthoritative() throws {
    let request = try request(requirements: .init(stateKinds: [.number]))
    #expect(throws: UIError.self) {
      try FoundationModelsDocumentProvider.plannedCalculationSchemaJSON(for: request, plan: plan(["describe"], kinds: ["text"]))
    }
    let data = try FoundationModelsDocumentProvider.plannedCalculationSchemaJSON(for: request, plan: plan(kinds: ["number", "text"]))
    let root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let fields = try #require(root["properties"] as? [String: [String: Any]])
    let items = try #require(fields["state"]?["items"] as? [String: Any])
    let variants = try #require(items["anyOf"] as? [[String: Any]])
    let kinds = variants.compactMap { ($0["properties"] as? [String: [String: Any]])?["kind"]?["enum"] as? [String] }.flatMap { $0 }
    #expect(kinds == ["number"])
  }
}
