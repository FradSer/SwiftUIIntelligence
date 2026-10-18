import Foundation
import SwiftUIIntelligence
@_spi(Testing) @testable import SwiftUIIntelligenceFoundationModels
import Testing

@Suite struct NativeReferenceProviderTests {
  private var signature: CalculationRegistry.Signature {
    .init(id: "compare", inputs: [:], outputs: [:],
      recordInputs: ["products": .init(fields: ["name": .text]),
        "measurements": .init(fields: ["productID": .text, "note": .text])],
      recordOutputs: ["result": .init(fields: ["name": .text])],
      recordReferences: [.init(input: "measurements", field: "productID", targetInput: "products")])
  }

  private func encode(_ value: Any) throws -> Data {
    try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
  }

  private func object(_ data: Data) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
  }

  @Test func collectionPromptKeepsSourceAndDependenciesWithoutDuplicatingGuidanceSchema() throws {
    let step = try #require(FoundationModelsDocumentProvider.referenceSteps(signatures: [signature]).first)
    let prompt = try FoundationModelsDocumentProvider.recordCollectionPrompt(conversation: "Exact synthetic source", feedback: "Correct the row ID", step: step, accepted: [:])
    #expect(prompt.contains("Exact synthetic source"))
    #expect(prompt.contains("Correct the row ID"))
    #expect(prompt.contains("products"))
    #expect(!prompt.contains("additionalProperties"))
    #expect(!prompt.contains("Collection schema:"))
  }

  @Test func collectionPromptRetainsExactReferenceTargetsAndMetadata() throws {
    let steps = try FoundationModelsDocumentProvider.referenceSteps(signatures: [signature])
    let step = try #require(steps.first { $0.input == "measurements" })
    let targetData = Data(#"{"id":"products","schema":{"fields":{"name":"text"}},"rows":[{"id":"actual-target-row","values":{"name":"Exact target name"}}]}"#.utf8)
    let target = try JSONDecoder().decode(RecordCollection.self, from: targetData)
    let prompt = try FoundationModelsDocumentProvider.recordCollectionPrompt(conversation: "Original source", feedback: "Keep source", step: step, accepted: ["compare": ["products": target]])
    #expect(prompt.contains("actual-target-row"))
    #expect(prompt.contains("Exact target name"))
    #expect(prompt.contains("targetInput"))
    #expect(prompt.contains("productID"))
    #expect(!prompt.contains("additionalProperties"))
  }

  @Test func collectionPromptPreservesHostInputDescription() throws {
    let described = CalculationRegistry.Signature(id: "compare", inputs: [:], outputs: [:],
      recordInputs: ["products": .init(fields: ["name": .text])], recordOutputs: ["result": .init(fields: ["name": .text])],
      recordInputDescriptions: ["products": "One row per supplied product; keep exact names."])
    let step = try #require(FoundationModelsDocumentProvider.referenceSteps(signatures: [described]).first)
    let prompt = try FoundationModelsDocumentProvider.recordCollectionPrompt(conversation: "Original source", feedback: "", step: step, accepted: [:], inputDescription: described.recordInputDescriptions["products"])
    #expect(prompt.contains("One row per supplied product; keep exact names."))
    #expect(prompt.contains("Original source"))
  }

  @Test func providerUsesCorrelatedComponentSchemaForDerivedTables() throws {
    let products = Data(#"{"id":"authored-products","schema":{"fields":{"name":"text"}},"rows":[]}"#.utf8)
    let measurements = Data(#"{"id":"authored-measurements","schema":{"fields":{"productID":"text","note":"text"}},"rows":[]}"#.utf8)
    let initial = try encode(["scalarRoles": ["compare": ["inputs": [:], "outputs": [:]]], "recordOutputs": ["compare": ["result": ["id": "authored-result"]]]])
    let source = try FoundationModelsDocumentProvider.assembleReferenceSource(initialData: initial, collections: ["compare": ["products": products, "measurements": measurements]], signatures: [signature])
    let bindings = Data(#"{"calculations":[{"id":"comparison","capability":"compare","inputs":{},"outputs":{},"recordInputs":{"products":"authored-products","measurements":"authored-measurements"},"recordOutputs":{"result":"authored-result"}}]}"#.utf8)
    let declarations = try NativeCalculationData.normalizeBindings(bindings, data: source, signatures: [signature])
    var layoutDeclarations = try object(declarations)
    layoutDeclarations["state"] = [["id": "count", "kind": "number", "value": 1]]
    let full = try NativeStagedSchema.layoutSchema(from: DocumentGenerationContract.schemaJSON(registeredCalculations: ["compare"]), declarations: encode(layoutDeclarations), signatures: [signature])
    let component = try FoundationModelsDocumentProvider.layoutComponentSchema(from: full, kind: .table, projected: true, slotID: "table", declarations: declarations, signatures: [signature])
    let root = try object(component)
    let defs = try #require(root["$defs"] as? [String: [String: Any]])
    let branches = try #require(defs["table"]?["anyOf"] as? [[String: Any]])
    var derivedBranches = 0
    for branch in branches {
      let fields = try #require(branch["properties"] as? [String: [String: Any]])
      if fields["recordSource"]?["enum"] as? [String] == ["authored-result"] {
        derivedBranches += 1
        #expect(fields["editableFields"] == nil)
      }
    }
    #expect(derivedBranches > 0)
    #expect(try FoundationModelsDocumentProvider.validateNativeLayoutSchema(component))
  }

  @Test func componentPromptKeepsOriginalContextAndExactSlotWithoutRepeatingPlan() throws {
    let slot = Data(#"{"id":"result","componentType":"table","purpose":"Show exact computed totals","projected":true}"#.utf8)
    let prompt = FoundationModelsDocumentProvider.componentPrompt(layoutPrompt: "Complete original source and catalog\nRetry feedback", slotData: slot)
    #expect(prompt.contains("Complete original source and catalog\nRetry feedback"))
    #expect(prompt.contains(String(decoding: slot, as: UTF8.self)))
    #expect(!prompt.contains("Complete model-authored layout plan"))
  }

  @Test func hostFactRejectionStopsBeforeCollectionAdmission() throws {
    let request = try DocumentGenerationRequest(messages: [.init(role: .user, content: "Exact products")],
      calculationSignatures: [signature], sourceInputValidation: { capability, input, _ in
        #expect(capability == "compare"); #expect(input == "products")
        throw UIError("Source facts do not match")
      })
    let step = try #require(FoundationModelsDocumentProvider.referenceSteps(signatures: [signature]).first)
    let data = Data(#"{"id":"products","schema":{"fields":{"name":"text"}},"rows":[{"id":"p","values":{"name":"Wrong"}}]}"#.utf8)
    #expect(throws: UIError.self) {
      try FoundationModelsDocumentProvider.acceptSourceCollection(data, step: step, accepted: [:], request: request)
    }
    let ordinary = try DocumentGenerationRequest(messages: request.messages, calculationSignatures: [signature])
    let admitted = try FoundationModelsDocumentProvider.acceptSourceCollection(data, step: step, accepted: [:], request: ordinary)
    #expect(admitted.originalData == data)
  }

  @Test func collectionInstructionsIncludeExactHostTaskWithoutSourceFacts() throws {
    let step = try #require(FoundationModelsDocumentProvider.referenceSteps(signatures: [signature]).first)
    let instructions = FoundationModelsDocumentProvider.recordCollectionInstructions(step: step, inputDescription: "Keep original product entities; no inferred rows.")
    #expect(instructions.contains("compare"))
    #expect(instructions.contains("products"))
    #expect(instructions.contains("Keep original product entities; no inferred rows."))
    #expect(instructions.contains("Do not infer missing business facts"))
  }

  // Given role data, when references are staged, then only input slots leave the initial schema.
  @Test func initialSchemaPreservesRolesOutputsAndStateConstraints() throws {
    let finite = DocumentGenerationContract.schemaJSON(registeredCalculations: ["compare"], includeRecords: true)
    let original = try NativeCalculationData.roleDataSchema(from: finite, signatures: [signature], allowedKinds: [.text])
    let schema = try object(FoundationModelsDocumentProvider.referenceSourceSchema(from: original))
    let fields = try #require(schema["properties"] as? [String: Any])
    let previous = try #require(object(original)["properties"] as? [String: Any])
    #expect(Set(fields.keys) == ["scalarRoles", "recordOutputs"])
    #expect(schema["required"] as? [String] == ["recordOutputs", "scalarRoles"])
    #expect(schema["additionalProperties"] as? Bool == false)
    for key in fields.keys { #expect(try encode(try #require(fields[key])) == encode(try #require(previous[key]))) }
    #expect(try FoundationModelsDocumentProvider.validateNativeLayoutSchema(encode(schema)))
  }

  // Given accepted target IDs, when one source is authored, then enums are exact and authored strings survive assembly.
  @Test func exactReferenceEnumsAndOriginalSourceObjects() throws {
    let steps = try FoundationModelsDocumentProvider.referenceSteps(signatures: [signature])
    #expect(steps.map(\.input) == ["products", "measurements"])
    let target = Data(#"{"id":"authored-products","schema":{"fields":{"name":"text"}},"rows":[{"id":"p-2","values":{"name":"Keep 007 / Ω"}}]}"#.utf8)
    let accepted = try NativeRecordReferencePlan.normalizeCollection(target, step: steps[0], accepted: [:])
    let schema = try object(NativeRecordReferencePlan.schemaForStep(steps[1], accepted: ["compare": ["products": accepted.collection]]))
    let fields = try #require(schema["properties"] as? [String: [String: Any]])
    let row = try #require(fields["rows"]?["items"] as? [String: Any])
    let rowFields = try #require(row["properties"] as? [String: [String: Any]])
    let values = try #require(rowFields["values"]?["properties"] as? [String: [String: Any]])
    #expect(values["productID"]?["enum"] as? [String] == ["p-2"])
    let source = Data(#"{"id":"authored-measurements","schema":{"fields":{"productID":"text","note":"text"}},"rows":[{"id":"m-9","values":{"productID":"p-2","note":"001.20 remains text\nΩ"}}]}"#.utf8)
    _ = try NativeRecordReferencePlan.normalizeCollection(source, step: steps[1], accepted: ["compare": ["products": accepted.collection]])
    let initial = try encode(["scalarRoles": ["compare": ["inputs": [:], "outputs": [:]]], "recordOutputs": ["compare": ["result": ["id": "authored-result"]]]])
    let data = try FoundationModelsDocumentProvider.assembleReferenceSource(initialData: initial,
      collections: ["compare": ["products": target, "measurements": source]], signatures: [signature])
    let declarations = try object(data.declarations)
    let records = try #require(declarations["records"] as? [[String: Any]])
    #expect(try encode(records[0]) == encode(object(source)))
    #expect(try encode(records[1]) == encode(object(target)))
    #expect(data.outputIDs == ["compare": ["result": "authored-result"]])
    #expect(data.recordInputRoles == ["compare": ["products": "authored-products", "measurements": "authored-measurements"]])
    let bindingSchema = try object(NativeCalculationData.bindingSchema(data: data, signatures: [signature]))
    let bindingProperties = try #require(bindingSchema["properties"] as? [String: [String: Any]])
    let bindingItems = try #require(bindingProperties["calculations"]?["items"] as? [String: Any])
    let variants = try #require(bindingItems["anyOf"] as? [[String: Any]])
    let maps = try #require(variants.first?["properties"] as? [String: [String: Any]])
    let inputs = try #require(maps["recordInputs"]?["properties"] as? [String: [String: Any]])
    #expect(inputs["products"]?["enum"] as? [String] == ["authored-products"])
    #expect(inputs["measurements"]?["enum"] as? [String] == ["authored-measurements"])
    #expect(declarations["calculations"] == nil)
    #expect(throws: UIError.self) {
      try FoundationModelsDocumentProvider.assembleReferenceSource(initialData: initial,
        collections: ["compare": ["products": target]], signatures: [signature])
    }
    var premature = try object(initial)
    premature["recordInputs"] = [String: Any]()
    #expect(throws: UIError.self) {
      try FoundationModelsDocumentProvider.assembleReferenceSource(initialData: encode(premature),
        collections: ["compare": ["products": target, "measurements": source]], signatures: [signature])
    }
  }

  // Given too many sources and destinations, when planning, then reject before model calls.
  @Test func collectionBudgetIncludesOutputDestinations() throws {
    let inputs = Dictionary(uniqueKeysWithValues: (0..<16).map { ("input-\($0)", RecordSchema(fields: ["name": .text])) })
    let large = CalculationRegistry.Signature(id: "large", inputs: [:], outputs: [:], recordInputs: inputs,
      recordOutputs: ["result": .init(fields: ["name": .text])])
    #expect(throws: UIError.self) { try FoundationModelsDocumentProvider.referenceSteps(signatures: [large]) }
    let atLimit = CalculationRegistry.Signature(id: "limit", inputs: [:], outputs: [:], recordInputs: inputs)
    #expect(try FoundationModelsDocumentProvider.referenceSteps(signatures: [atLimit]).count == 16)
    #expect(try FoundationModelsDocumentProvider.referenceSteps(signatures: [signature]).count == 2)
  }
}
