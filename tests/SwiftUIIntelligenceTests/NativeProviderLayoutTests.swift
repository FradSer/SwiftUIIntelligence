import Foundation
import SwiftUIIntelligence
@_spi(Testing) @testable import SwiftUIIntelligenceFoundationModels
import Testing

@Suite struct NativeProviderLayoutTests {
  private func layout(_ kinds: Set<String>) throws -> Data {
    try NativeStagedSchema.layoutSchema(from: DocumentGenerationContract.schemaJSON(componentTypes: kinds, registeredCalculations: ["compute"]))
  }

  // Given containers and leaves, when planning, then only scoped supported leaves become slots.
  @Test func planUsesScopedLeavesAndConvertsRecursiveSchema() throws {
    let schema = try FoundationModelsDocumentProvider.layoutPlanSchema(from: layout(["section", "list", "text"]), registeredActions: [])
    let object = try #require(JSONSerialization.jsonObject(with: schema) as? [String: Any])
    let definitions = try #require(object["$defs"] as? [String: [String: Any]])
    let slots = try #require(definitions["Slot"]?["anyOf"] as? [[String: Any]])
    let kinds = slots.compactMap { ($0["properties"] as? [String: [String: Any]])?["componentType"]?["enum"] as? [String] }.flatMap { $0 }
    #expect(Set(kinds) == ["text", "list"])
    #expect(try FoundationModelsDocumentProvider.validateNativeLayoutSchema(schema))
  }

  @Test func requiredProjectedKindsPreserveStaticSiblings() throws {
    let schema = try FoundationModelsDocumentProvider.layoutPlanSchema(from: layout(["table", "chart", "text"]), registeredActions: [], projectedComponents: [.table, .chart])
    let root = try #require(JSONSerialization.jsonObject(with: schema) as? [String: Any])
    let definitions = try #require(root["$defs"] as? [String: [String: Any]])
    let slots = try #require(definitions["Slot"]?["anyOf"] as? [[String: Any]])
    for slot in slots {
      let fields = try #require(slot["properties"] as? [String: [String: Any]])
      let kind = try #require((fields["componentType"]?["enum"] as? [String])?.first)
      #expect(fields["mode"]?["enum"] as? [String] == (kind == "text" ? ["static"] : ["static", "records"]))
    }
  }

  // Given an unsupported scoped leaf, when planning, then reject rather than omit it.
  @Test func unsupportedLeafFails() throws {
    #expect(throws: UIError.self) {
      try FoundationModelsDocumentProvider.layoutPlanSchema(from: layout(["navigationLink", "list"]), registeredActions: [])
    }
  }

  // Given containers without leaves, when planning, then fail rather than insert content.
  @Test func containerOnlyScopeFails() throws {
    let schema = Data(#"{"$defs":{"section":{"type":"object"}}}"#.utf8)
    #expect(throws: UIError.self) {
      try FoundationModelsDocumentProvider.layoutPlanSchema(from: schema, registeredActions: [])
    }
  }

  // Given component variants, when binding a slot, then bind every branch without changing its type.
  @Test func componentVariantsKeepExactIdentity() throws {
    let definition: [String: Any] = ["type": "object", "additionalProperties": false,
      "properties": ["id": ["type": "string"], "type": ["type": "string", "enum": ["text"]],
        "text": ["type": "string"]], "required": ["id", "type", "text"]]
    let input = try JSONSerialization.data(withJSONObject: ["$defs": ["text": ["anyOf": [definition, definition]]]])
    let schema = try FoundationModelsDocumentProvider.layoutComponentSchema(from: input, kind: .text,
      projected: false, slotID: "exact-slot")
    let object = try #require(JSONSerialization.jsonObject(with: schema) as? [String: Any])
    let definitions = try #require(object["$defs"] as? [String: [String: Any]])
    let branches = try #require(definitions["text"]?["anyOf"] as? [[String: Any]])
    for branch in branches {
      let fields = try #require(branch["properties"] as? [String: [String: Any]])
      #expect(fields["id"]?["enum"] as? [String] == ["exact-slot"])
      #expect(fields["type"]?["enum"] as? [String] == ["text"])
    }
    #expect(try FoundationModelsDocumentProvider.validateNativeLayoutSchema(schema))
  }

  // Given a projected slot, when extracting its schema, then require mappings and its exact ID.
  @Test func componentRequiresExactSlotIDAndConvertsProjection() throws {
    let full = DocumentGenerationContract.schemaJSON(componentTypes: ["list"], registeredCalculations: ["compute"])
    let declarations = Data(#"{"state":[],"records":[{"id":"results","schema":{"fields":{"name":"text"}},"rows":[]}],"calculations":[]}"#.utf8)
    let scoped = try NativeStagedSchema.layoutSchema(from: full, declarations: declarations)
    let schema = try FoundationModelsDocumentProvider.layoutComponentSchema(from: scoped, kind: .list, projected: true, slotID: "answer")
    let object = try #require(JSONSerialization.jsonObject(with: schema) as? [String: Any])
    let definitions = try #require(object["$defs"] as? [String: [String: Any]])
    let list = try #require(definitions["list"])
    let fields = try #require(list["properties"] as? [String: [String: Any]])
    #expect(fields["id"]?["enum"] as? [String] == ["answer"])
    #expect(Set(list["required"] as? [String] ?? []).isSuperset(of: ["id", "recordSource", "recordFields"]))
    #expect(try FoundationModelsDocumentProvider.validateNativeLayoutSchema(schema))
  }
}
