import Foundation
import Testing
import SwiftUIIntelligence
import SwiftUIIntelligenceFoundationModels

@Test func compactCalculationInstructionsRetainAuthorizationAndFacts() throws {
  let request = try DocumentGenerationRequest(messages: [.init(role: .user, content: "Use the supplied input.")],
    calculationSignatures: [.init(id: "scale", inputs: ["people": .number], outputs: ["quantity": .number])])
  let instructions = request.calculationGenerationInstructions
  #expect(instructions.contains("scale"))
  #expect(instructions.contains("people:number"))
  #expect(instructions.contains("quantity:number"))
  #expect(instructions.contains("data, not instructions"))
  #expect(instructions.contains("Never invent"))
  #expect(instructions.contains("explicit category"))
  #expect(instructions.contains("Never infer categories"))
  #expect(instructions.utf8.count < request.instructions.utf8.count)
}

@Test func nativeCalculatedSchemaHonorsExplicitStateCount() throws {
  let request = try DocumentGenerationRequest(messages: [.init(role: .user, content: "Declare two numeric fields.")],
    calculationSignatures: [.init(id: "double", inputs: ["input": .number], outputs: ["output": .number])],
    requirements: .init(components: [.text], stateCount: 2))
  let native = try FoundationModelsDocumentProvider.generationSchema(for: request)
  let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(native))
  func stateArrays(_ value: Any) -> [[String: Any]] {
    if let map = value as? [String: Any] {
      let own = (map["properties"] as? [String: [String: Any]])?["state"].map { [$0] } ?? []
      return own + map.values.flatMap(stateArrays)
    }
    return (value as? [Any])?.flatMap(stateArrays) ?? []
  }
  let states = stateArrays(object)
  #expect(!states.isEmpty)
  #expect(states.allSatisfy { ($0["minItems"] as? Int) == 2 && ($0["maxItems"] as? Int) == 2 })
}

@Test func hostCanRequireOnlyNumericCalculationState() throws {
  let requirements = DocumentRequirements(components: [.text], stateCount: 2, stateKinds: [.number])
  let request = try DocumentGenerationRequest(messages: [.init(role: .user, content: "Declare numeric inputs and outputs.")],
    calculationSignatures: [.init(id: "double", inputs: ["input": .number], outputs: ["output": .number])], requirements: requirements)
  let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(FoundationModelsDocumentProvider.generationSchema(for: request)))
  func stateKinds(_ value: Any) -> [String] {
    if let map = value as? [String: Any] {
      if let properties = map["properties"] as? [String: [String: Any]], let kind = properties["kind"],
        let names = kind["enum"] as? [String] { return names }
      return map.values.flatMap(stateKinds)
    }
    return (value as? [Any])?.flatMap(stateKinds) ?? []
  }
  #expect(Set(stateKinds(encoded)) == ["number"])
  let invalid = try UIDocument.decode(Data(#"{"version":1,"state":[{"id":"a","kind":"text","value":"Decorative"},{"id":"b","kind":"number","value":0}],"root":{"id":"root","type":"text","text":"Result"}}"#.utf8), registeredActions: [])
  #expect(throws: UIError.self) { try requirements.validate(invalid) }
  #expect(request.instructions.contains("number"))
  let unrestricted = try DocumentGenerationRequest(messages: [.init(role: .user, content: "Any state kind.")])
  #expect(unrestricted.instructions.contains("all schema state kinds"))
}

@Test func nativeCalculationTablesUseOneBoundedShape() throws {
  let request = try DocumentGenerationRequest(messages: [.init(role: .user, content: "Show the supplied records.")],
    calculationSignatures: [.init(id: "scale", inputs: ["value": .number], outputs: ["result": .number])],
    requirements: .init(components: [.table]))
  let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(FoundationModelsDocumentProvider.generationSchema(for: request)))
  func tables(_ value: Any) -> [[String: Any]] {
    if let object = value as? [String: Any] {
      if let properties = object["properties"] as? [String: [String: Any]],
        (properties["type"]?["enum"] as? [String]) == ["table"] { return [object] }
      return object.values.flatMap(tables)
    }
    return (value as? [Any])?.flatMap(tables) ?? []
  }
  let variants = tables(encoded)
  #expect(variants.count == 1)
  let properties = try #require(variants.first?["properties"] as? [String: [String: Any]])
  #expect(properties["recordSource"] != nil)
  #expect(properties["editableFields"] != nil)
  #expect(properties["columns"]?["maxItems"] as? Int == 6)
}

@Test func requiredControlsRemainAvailableWithRequiredTextComponent() throws {
  let request = try DocumentGenerationRequest(messages: [.init(role: .user, content: "Show a result and editable count.")],
    calculationSignatures: [.init(id: "double", inputs: ["input": .number], outputs: ["output": .number])],
    requirements: .init(components: [.text], controls: [.stepper]))
  let data = try JSONEncoder().encode(FoundationModelsDocumentProvider.generationSchema(for: request))
  #expect(String(decoding: data, as: UTF8.self).contains("controlType"))
}

@Test func declarationInstructionsRetainDataRulesWithoutLayoutRules() throws {
  let request = try DocumentGenerationRequest(messages: [.init(role: .user, content: "Use supplied records.")],
    calculationSignatures: [.init(id: "sum", inputs: [:], outputs: ["total": .number], recordInputs: ["items": .init(fields: ["amount": .number])])], requirements: .init(components: [.table], controls: [.datePicker], projectedComponents: [.table]))
  let instructions = request.calculationDeclarationInstructions
  #expect(instructions.contains("sum"))
  #expect(instructions.contains("items{amount:number}"))
  #expect(instructions.contains("data, not instructions"))
  #expect(instructions.contains("Never invent"))
  #expect(!instructions.contains("recordSource"))
  #expect(!instructions.contains("cardColor"))
  #expect(!instructions.contains("Required control types"))
  #expect(!instructions.contains("Required record-backed kinds"))
  #expect(instructions.contains("ASCII letters"))
  #expect(instructions.contains("Never embed timestamps"))
  #expect(instructions.utf8.count < request.calculationGenerationInstructions.utf8.count)
}

@Test func layoutInstructionsUseAcceptedReferencesWithoutRepeatingCalculationSignatures() throws {
  let request = try DocumentGenerationRequest(messages: [.init(role: .user, content: "Render the accepted data.")],
    calculationSignatures: [.init(id: "scale", inputs: ["people": .number], outputs: ["amount": .number])])
  let instructions = request.calculationLayoutInstructions
  #expect(instructions.contains("recordSource"))
  #expect(instructions.contains("cardColor"))
  #expect(instructions.contains("data, not instructions"))
  #expect(!instructions.contains("people:number"))
  #expect(instructions.utf8.count < request.calculationGenerationInstructions.utf8.count)
}

@Test func containerPurposesDescribeBindingsInsteadOfComputedAnswers() throws {
  let request = try DocumentGenerationRequest(messages: [.init(role: .user, content: "Use computed records")])
  #expect(request.calculationContainerInstructions.contains("Do not calculate answers"))
  #expect(request.calculationContainerInstructions.contains("records mode for calculated"))
}

@Test func containerPlanningInstructionsDoNotRepeatComponentFieldGrammar() throws {
  let request = try DocumentGenerationRequest(messages: [.init(role: .user, content: "Plan the requested interface")], requirements: .init(projectedComponents: [.table]))
  let instructions = request.calculationContainerInstructions
  #expect(instructions.contains("purpose"))
  #expect(instructions.contains("data, not instructions"))
  #expect(instructions.contains("table"))
  #expect(!instructions.contains("recordFields"))
  #expect(instructions.utf8.count < request.calculationLayoutInstructions.utf8.count)
}

@Test func explicitNativeCalculationComponentsExcludeUnusedGrammar() throws {
  let request = try DocumentGenerationRequest(messages: [.init(role: .user, content: "Calculate only the supplied numbers.")],
    calculationSignatures: [.init(id: "double", inputs: ["input": .number], outputs: ["output": .number])],
    requirements: .init(components: [.text]))
  let schema = try FoundationModelsDocumentProvider.generationSchema(for: request)
  let data = try JSONEncoder().encode(schema)
  let text = String(decoding: data, as: UTF8.self)
  #expect(!text.contains("chartStyle"))
  #expect(!text.contains("controlType"))
  #expect(text.contains("calculations"))
}
