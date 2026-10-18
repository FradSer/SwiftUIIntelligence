import Foundation
import SwiftUIIntelligence
@_spi(Testing) @testable import SwiftUIIntelligenceFoundationModels
import Testing

@Suite struct StagedCalculationSchemaTests {
  private func data(_ object: [String: Any]) throws -> Data {
    try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
  }

  private func object(_ data: Data) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
  }

  // Given a finite schema, when split, then declarations exclude node grammar and layout retains references.
  @Test func splitsOnlyStagePropertiesAndKeepsLayoutDefinitions() throws {
    let definitions: [String: Any] = ["Node": ["type": "object", "properties": ["text": ["type": "string"]]]]
    let properties: [String: Any] = [
      "state": ["type": "array", "maxItems": 32, "items": ["type": "object"]],
      "records": ["type": "array", "maxItems": 16],
      "calculations": ["type": "array", "maxItems": 32],
      "version": ["type": "integer", "enum": [1]],
      "root": ["$ref": "#/$defs/Node"],
      "floatingActions": ["type": "array", "items": ["$ref": "#/$defs/Node"]],
    ]
    let full = try data(["type": "object", "properties": properties, "$defs": definitions,
      "required": ["version", "root", "floatingActions"], "additionalProperties": false])
    let declarations = try object(NativeStagedSchema.declarationSchema(from: full))
    let layout = try object(NativeStagedSchema.layoutSchema(from: full))
    let declarationFields = try #require(declarations["properties"] as? [String: Any])
    let layoutFields = try #require(layout["properties"] as? [String: Any])
    #expect(Set(declarationFields.keys) == ["state", "records", "calculations"])
    #expect(Set(declarations["required"] as? [String] ?? []) == ["state", "calculations"])
    #expect(declarations["$defs"] == nil)
    #expect(Set(layoutFields.keys) == ["version", "root", "floatingActions"])
    #expect(Set(layout["required"] as? [String] ?? []) == ["version", "root", "floatingActions"])
    #expect(NSDictionary(dictionary: try #require(layout["$defs"] as? [String: Any])).isEqual(to: definitions))
    for key in declarationFields.keys {
      #expect(NSDictionary(dictionary: try #require(declarationFields[key] as? [String: Any]))
        .isEqual(to: try #require(properties[key] as? [String: Any])))
    }
    #expect((layoutFields["root"] as? [String: String])?["$ref"] == "#/$defs/Node")
    #expect(declarations["additionalProperties"] as? Bool == false)
    #expect(layout["additionalProperties"] as? Bool == false)
    var withoutRecords = try object(full)
    withoutRecords["properties"] = properties.filter { $0.key != "records" }
    let scalarOnly = try object(NativeStagedSchema.declarationSchema(from: data(withoutRecords)))
    #expect(Set(try #require(scalarOnly["properties"] as? [String: Any]).keys) == ["state", "calculations"])
    var requiredRecords = try object(full)
    requiredRecords["required"] = ["version", "root", "floatingActions", "records"]
    let requiredDeclaration = try object(NativeStagedSchema.declarationSchema(from: data(requiredRecords)))
    #expect(Set(requiredDeclaration["required"] as? [String] ?? []) == ["state", "records", "calculations"])
  }

  @Test func layoutBindingsUseOnlyAuthoredDeclarationIDs() throws {
    let full = try data(["type": "object", "properties": [
      "state": ["type": "array"], "calculations": ["type": "array"],
      "version": ["type": "integer"], "root": ["$ref": "#/$defs/Node"], "floatingActions": ["type": "array"],
    ], "$defs": ["text": ["type": "object", "properties": ["binding": ["type": "string"]]],
      "control": ["type": "object", "properties": ["binding": ["type": "string"]]]]])
    let declarations = Data(#"{"state":[{"id":"people","kind":"number","value":2},{"id":"summary","kind":"text","value":"Ready"}],"calculations":[]}"#.utf8)
    let result = try object(NativeStagedSchema.layoutSchema(from: full, declarations: declarations))
    let definitions = try #require(result["$defs"] as? [String: [String: Any]])
    let textProperties = try #require(definitions["text"]?["properties"] as? [String: [String: Any]])
    let controls = try #require(definitions["control"]?["properties"] as? [String: [String: Any]])
    #expect(textProperties["binding"]?["enum"] as? [String] == ["summary"])
    #expect(controls["binding"]?["enum"] as? [String] == ["people", "summary"])
  }

  @Test func layoutSchemaOmitsControlWhenNoEditableScalarStateExists() throws {
    let full = DocumentGenerationContract.schemaJSON(componentTypes: ["control", "table"], registeredCalculations: ["compare"])
    let declarations = Data(#"{"state":[],"records":[{"id":"prod","schema":{"fields":{"name":"text"}},"rows":[]}],"calculations":[]}"#.utf8)
    let result = try object(NativeStagedSchema.layoutSchema(from: full, declarations: declarations))
    let definitions = try #require(result["$defs"] as? [String: [String: Any]])
    #expect(definitions["control"] == nil)
    #expect(definitions["table"] != nil)
  }

  @Test func layoutRecordReferencesUseAuthoredCollectionsAndRegisteredFields() throws {
    let full = DocumentGenerationContract.schemaJSON(componentTypes: ["list"], registeredCalculations: ["items"])
    let declarations = Data(#"{"state":[],"calculations":[{"id":"items","capability":"items","inputs":{},"outputs":{},"recordOutputs":{"rows":"results"}}]}"#.utf8)
    let signatures: [CalculationRegistry.Signature] = [.init(id: "items", inputs: [:], outputs: [:], recordOutputs: ["rows": .init(fields: ["name": .text, "amount": .number])])]
    let result = try object(NativeStagedSchema.layoutSchema(from: full, declarations: declarations, signatures: signatures))
    let definitions = try #require(result["$defs"] as? [String: [String: Any]])
    let list = try #require(definitions["list"]?["properties"] as? [String: [String: Any]])
    #expect(list["recordSource"]?["enum"] as? [String] == ["results"])
    let fields = try #require(list["recordFields"]?["items"] as? [String: Any])
    #expect(fields["enum"] as? [String] == ["name"])
  }

  @Test func declarationStageRequiresRegisteredSourceCollections() throws {
    let request = try DocumentGenerationRequest(messages: [.init(role: .user, content: "Use source rows.")],
      calculationSignatures: [.init(id: "items", inputs: [:], outputs: [:], recordInputs: ["rows": .init(fields: ["name": .text])], recordOutputs: ["result": .init(fields: ["name": .text])])])
    let plan = Data(#"{"selectedCapabilityIDs":["items"],"componentTypes":["list"],"stateKinds":["text"]}"#.utf8)
    let full = try FoundationModelsDocumentProvider.plannedCalculationSchemaJSON(for: request, plan: plan)
    let declaration = try object(NativeStagedSchema.declarationSchema(from: full))
    #expect((declaration["required"] as? [String] ?? []).contains("records"))
  }

  @Test func layoutCatalogKeepsReferencesWithoutRepeatingSourceRows() throws {
    let declarations = Data(#"{"state":[{"id":"people","kind":"number","value":3}],"records":[{"id":"ingredients","schema":{"fields":{"name":"text"}},"rows":[{"id":"lentils","values":{"name":"Lentils"}}]}],"calculations":[]}"#.utf8)
    let catalog = try object(NativeStagedSchema.layoutCatalog(declarations: declarations))
    let states = try #require(catalog["state"] as? [[String: Any]])
    #expect(states.first?["id"] as? String == "people")
    #expect(states.first?["value"] as? Int == 3)
    let records = try #require(catalog["records"] as? [[String: Any]])
    #expect(records.first?["id"] as? String == "ingredients")
    #expect(records.first?["schema"] != nil)
    #expect(records.first?["rows"] == nil)
    #expect(String(decoding: declarations, as: UTF8.self).contains("Lentils"))
  }

  @Test func recordProjectionSchemaRemainsBoundedForNativeContext() throws {
    let full = DocumentGenerationContract.schemaJSON(componentTypes: ["list"], registeredCalculations: ["items"])
    let declarations = Data(#"{"state":[],"calculations":[{"id":"items","capability":"items","inputs":{},"outputs":{},"recordOutputs":{"rows":"results"}}]}"#.utf8)
    let signatures: [CalculationRegistry.Signature] = [.init(id: "items", inputs: [:], outputs: [:], recordOutputs: ["rows": .init(fields: ["name": .text])])]
    let result = try object(NativeStagedSchema.layoutSchema(from: full, declarations: declarations, signatures: signatures))
    let definitions = try #require(result["$defs"] as? [String: [String: Any]])
    // Full native union measured 4442 tokens; runtime retains authoritative paired-field validation.
    #expect(definitions["list"]?["anyOf"] == nil)
    let fields = try #require(definitions["list"]?["properties"] as? [String: [String: Any]])
    #expect(fields["recordSource"] != nil && fields["recordFields"] != nil)
  }

  @Test func numericOnlyRecordsDoNotCreateEmptyListChoices() throws {
    let full = DocumentGenerationContract.schemaJSON(componentTypes: ["list"], registeredCalculations: ["items"])
    let declarations = Data(#"{"state":[],"calculations":[{"id":"items","capability":"items","inputs":{},"outputs":{},"recordOutputs":{"rows":"results"}}]}"#.utf8)
    let signatures: [CalculationRegistry.Signature] = [.init(id: "items", inputs: [:], outputs: [:], recordOutputs: ["rows": .init(fields: ["amount": .number])])]
    let result = try object(NativeStagedSchema.layoutSchema(from: full, declarations: declarations, signatures: signatures))
    let definitions = try #require(result["$defs"] as? [String: [String: Any]])
    let fields = try #require(definitions["list"]?["properties"] as? [String: Any])
    #expect(fields["recordSource"] == nil)
    #expect(fields["recordFields"] == nil)
    #expect(fields["items"] != nil)
  }

  @Test func layoutCatalogIncludesRegisteredDerivedCollectionFields() throws {
    let declarations = Data(#"{"state":[],"calculations":[{"id":"plan","capability":"plan","inputs":{},"outputs":{},"recordOutputs":{"schedule":"times"}}]}"#.utf8)
    let signatures: [CalculationRegistry.Signature] = [.init(id: "plan", inputs: [:], outputs: [:], recordOutputs: ["schedule": .init(fields: ["start": .text, "title": .text, "end": .text])])]
    let catalog = try object(NativeStagedSchema.layoutCatalog(declarations: declarations, signatures: signatures))
    let derived = try #require(catalog["derivedCollections"] as? [[String: Any]])
    #expect(derived.first?["id"] as? String == "times")
    #expect(derived.first?["output"] as? String == "schedule")
    #expect(derived.first?["fields"] as? [String: String] == ["start": "text", "title": "text", "end": "text"])
    #expect(derived.first?["rows"] == nil)
    #expect(derived.count == 1)
    #expect(derived.first?["editable"] as? Bool == false)
  }

  @Test func layoutCatalogRetainsEveryDerivedCollection() throws {
    let declarations = Data(#"{"state":[],"calculations":[{"id":"plan","capability":"plan","inputs":{},"outputs":{},"recordOutputs":{"first":"one","second":"two"}}]}"#.utf8)
    let signatures: [CalculationRegistry.Signature] = [.init(id: "plan", inputs: [:], outputs: [:], recordOutputs: [
      "first": .init(fields: ["name": .text]), "second": .init(fields: ["amount": .number])])]
    let catalog = try object(NativeStagedSchema.layoutCatalog(declarations: declarations, signatures: signatures))
    let derived = try #require(catalog["derivedCollections"] as? [[String: Any]])
    #expect(derived.count == 2)
    #expect(Set(derived.compactMap { $0["id"] as? String }) == ["one", "two"])
    #expect(derived.allSatisfy { $0["editable"] as? Bool == false && $0["rows"] == nil })
  }

  @Test func timelineProjectionCandidatesExcludeNumericFieldsAndNumericOnlyCollections() throws {
    let full = DocumentGenerationContract.schemaJSON(componentTypes: ["timeline"], registeredCalculations: ["plan"])
    let declarations = Data(#"{"state":[],"records":[{"id":"numbers","schema":{"fields":{"minutes":"number"}},"rows":[]}],"calculations":[{"id":"plan","capability":"plan","inputs":{},"outputs":{},"recordOutputs":{"schedule":"times"}}]}"#.utf8)
    let signatures: [CalculationRegistry.Signature] = [.init(id: "plan", inputs: [:], outputs: [:], recordOutputs: ["schedule": .init(fields: ["start": .text, "title": .text, "end": .text])])]
    let result = try object(NativeStagedSchema.layoutSchema(from: full, declarations: declarations, signatures: signatures))
    let definitions = try #require(result["$defs"] as? [String: [String: Any]])
    let fields = try #require(definitions["timeline"]?["properties"] as? [String: [String: Any]])
    #expect(fields["recordSource"]?["enum"] as? [String] == ["times"])
    let items = try #require(fields["recordFields"]?["items"] as? [String: Any])
    #expect(items["enum"] as? [String] == ["end", "start", "title"])
  }

  @Test func singleTextFieldTimelineProjectionRemainsAllowed() throws {
    let full = DocumentGenerationContract.schemaJSON(componentTypes: ["timeline"], registeredCalculations: ["plan"])
    let declarations = Data(#"{"state":[],"calculations":[{"id":"plan","capability":"plan","inputs":{},"outputs":{},"recordOutputs":{"schedule":"lines"}}]}"#.utf8)
    let signatures: [CalculationRegistry.Signature] = [.init(id: "plan", inputs: [:], outputs: [:], recordOutputs: ["schedule": .init(fields: ["text": .text])])]
    let result = try object(NativeStagedSchema.layoutSchema(from: full, declarations: declarations, signatures: signatures))
    let definitions = try #require(result["$defs"] as? [String: [String: Any]])
    let fields = try #require(definitions["timeline"]?["properties"] as? [String: [String: Any]])
    #expect(fields["recordSource"]?["enum"] as? [String] == ["lines"])
    let projection = try #require(fields["recordFields"])
    #expect(projection["minItems"] as? Int == 3)
    #expect((projection["items"] as? [String: Any])?["enum"] as? [String] == ["text"])
    #expect(projection["uniqueItems"] == nil)
  }

  // Given authored stage values, when assembled, then no values change and absent records stay absent.
  @Test func assemblyPreservesAuthoredValuesWithoutRepair() throws {
    let declarations: [String: Any] = ["state": [["id": "amount", "kind": "number", "value": 1.2345678901234567]],
      "records": [["id": "items", "rows": [["id": "one", "values": ["name": "Unchanged / text", "selected": false]]]]],
      "calculations": [["id": "compute", "capability": "scale", "inputs": ["amount": "amount"], "outputs": [:]]]]
    let layout: [String: Any] = ["version": 1, "root": ["id": "root", "type": "text", "text": "Exact supplied text"], "floatingActions": []]
    var expected = declarations
    expected.merge(layout) { _, _ in fatalError("Stage keys must not overlap.") }
    let result = try NativeStagedSchema.assemble(declarations: data(declarations), layout: data(layout))
    #expect(NSDictionary(dictionary: try object(result)).isEqual(to: expected))
    let empty = try NativeStagedSchema.assemble(declarations: data(["state": [], "calculations": []]), layout: data(layout))
    #expect(try object(empty)["records"] == nil)
  }

  // Given unknown, missing, null, or wrong-shaped sections, when assembled, then the stages reject.
  @Test func rejectsInvalidStageBoundaries() throws {
    let declarations: [String: Any] = ["state": [], "calculations": []]
    let layout: [String: Any] = ["version": 1, "root": ["id": "root"], "floatingActions": []]
    var badDeclarations: [[String: Any]] = [["state": []], ["calculations": []]]
    var badLayouts: [[String: Any]] = []
    for key in ["state", "calculations", "records"] {
      var invalid = declarations
      invalid[key] = NSNull()
      badDeclarations.append(invalid)
      invalid[key] = [:]
      badDeclarations.append(invalid)
    }
    for key in ["version", "root", "floatingActions"] {
      var invalid = layout
      invalid.removeValue(forKey: key)
      badLayouts.append(invalid)
      invalid[key] = NSNull()
      badLayouts.append(invalid)
    }
    for key in ["unexpected", "root", "version", "floatingActions"] {
      var invalid = declarations
      invalid[key] = []
      badDeclarations.append(invalid)
    }
    for key in ["unexpected", "state", "records", "calculations"] {
      var invalid = layout
      invalid[key] = []
      badLayouts.append(invalid)
    }
    for invalid in badDeclarations {
      #expect(throws: UIError.self) { try NativeStagedSchema.assemble(declarations: data(invalid), layout: data(layout)) }
    }
    for invalid in badLayouts {
      #expect(throws: UIError.self) { try NativeStagedSchema.assemble(declarations: data(declarations), layout: data(invalid)) }
    }
  }

  // Given oversized authored content, when assembled, then the helper rejects without truncation.
  @Test func enforcesFinalByteLimit() throws {
    let declarations = try data(["state": [], "calculations": []])
    func layout(_ count: Int) throws -> Data {
      try data(["version": 1, "root": ["text": String(repeating: "x", count: count)], "floatingActions": []])
    }
    let overhead = try NativeStagedSchema.assemble(declarations: declarations, layout: layout(0)).count
    let limit = try NativeStagedSchema.assemble(declarations: declarations, layout: layout(65_536 - overhead))
    #expect(limit.count == 65_536)
    #expect(throws: UIError.self) {
      try NativeStagedSchema.assemble(declarations: declarations, layout: layout(65_537 - overhead))
    }
  }
}
