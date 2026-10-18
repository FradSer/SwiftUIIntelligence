import Foundation
import SwiftUIIntelligence
@_spi(Testing) @testable import SwiftUIIntelligenceFoundationModels
import Testing

@Suite struct NativeComponentLayoutTests {
  private func data(_ object: [String: Any]) throws -> Data {
    try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
  }

  private func object(_ data: Data) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
  }

  private func layout() throws -> Data {
    let full = DocumentGenerationContract.schemaJSON(registeredCalculations: ["compute"])
    let declarations = Data(#"{"state":[{"id":"count","kind":"number","value":2}],"records":[{"id":"results","schema":{"fields":{"name":"text","amount":"number","series":"text"}},"rows":[]}],"calculations":[]}"#.utf8)
    return try NativeStagedSchema.layoutSchema(from: full, declarations: declarations)
  }

  @Test func schemaConverterOrdersProjectionSourceAndFieldsBeforeColumns() throws {
    let schema: [String: Any] = [
      "type": "object",
      "properties": [
        "columns": ["type": "array", "items": ["type": "string"]],
        "recordFields": ["type": "array", "items": ["type": "string"]],
        "recordSource": ["type": "string"],
        "id": ["type": "string"],
      ]
    ]
    let desc = try FoundationModelsDocumentProvider.nativeSchemaDescription(JSONSerialization.data(withJSONObject: schema))
    let schemaData = Data(desc.utf8)
    let json = try #require(JSONSerialization.jsonObject(with: schemaData) as? [String: Any])
    let order = try #require(json["x-order"] as? [String])
    let sourceIdx = try #require(order.firstIndex(of: "recordSource"))
    let fieldsIdx = try #require(order.firstIndex(of: "recordFields"))
    let colsIdx = try #require(order.firstIndex(of: "columns"))
    #expect(sourceIdx < fieldsIdx)
    #expect(fieldsIdx < colsIdx)
  }

  @Test func definitionReferencesDecodeFragmentsAndRejectMalformedEscapes() throws {
    for (reference, name, valid) in [
      ("Point%20Data", "Point Data", true), ("Point~0Data", "Point~Data", true),
      ("Point~1Data", "Point/Data", true), ("Point~2Data", "Point~2Data", false),
      ("Point%ZZ", "Point%ZZ", false),
    ] {
      let source = try data(["$defs": [
        "text": ["type": "object", "properties": ["type": ["enum": ["text"]], "text": ["$ref": "#/$defs/\(reference)"]]],
        name: ["type": "string"],
      ]])
      if valid {
        let result = try object(NativeComponentLayout.componentSchema(from: source, kind: .text, projected: false))
        #expect((result["$defs"] as? [String: Any])?[name] != nil)
      } else {
        #expect(throws: UIError.self) { try NativeComponentLayout.componentSchema(from: source, kind: .text, projected: false) }
      }
    }
  }

  @Test func encodedDefinitionPathPrefixResolvesAfterDecoding() throws {
    for reference in ["#/%24defs/Point", "#%2F$defs%2FPoint"] {
      let source = try data(["$defs": [
        "text": ["type": "object", "properties": ["type": ["enum": ["text"]], "text": ["$ref": reference]]],
        "Point": ["type": "string"],
      ]])
      let result = try object(NativeComponentLayout.componentSchema(from: source, kind: .text, projected: false))
      #expect((result["$defs"] as? [String: Any])?["Point"] != nil)
    }
  }

  // Given scoped records, when projection is required, then both references are required without selecting values.
  @Test func projectedListRequiresBothReferencesAndPreservesStaticItems() throws {
    let source = try layout()
    let result = try object(NativeComponentLayout.componentSchema(from: source, kind: .list, projected: true))
    #expect(result["$ref"] as? String == "#/$defs/list")
    #expect(result["properties"] == nil)
    let definitions = try #require(result["$defs"] as? [String: [String: Any]])
    #expect(Set(definitions.keys) == ["list"])
    let list = try #require(definitions["list"])
    let fields = try #require(list["properties"] as? [String: [String: Any]])
    let original = try #require((try object(source)["$defs"] as? [String: [String: Any]])?["list"])
    let originalFields = try #require(original["properties"] as? [String: Any])
    #expect(Set(list["required"] as? [String] ?? []).isSuperset(of: ["recordSource", "recordFields", "items"]))
    #expect(fields["recordSource"]?["enum"] as? [String] == ["results"])
    #expect(fields["type"]?["enum"] as? [String] == ["list"])
    #expect(NSDictionary(dictionary: try #require(fields["items"])).isEqual(to: try #require(originalFields["items"] as? [String: Any])))
    #expect(fields["recordSource"]?["const"] == nil)
    #expect(fields["recordFields"]?["const"] == nil)
  }

  // Given static mode, when extracted, then record properties and their required entries are absent.
  @Test func staticComponentsExcludeProjectionGrammar() throws {
    let source = try layout()
    for kind: UINode.Kind in [.text, .control, .list, .table, .chart, .timeline] {
      let result = try object(NativeComponentLayout.componentSchema(from: source, kind: kind, projected: false))
      let definitions = try #require(result["$defs"] as? [String: [String: Any]])
      func check(_ node: [String: Any]) throws {
        if let branches = node["anyOf"] as? [[String: Any]] {
          for branch in branches { try check(branch) }
          return
        }
        let fields = try #require(node["properties"] as? [String: [String: Any]])
        #expect(fields["type"]?["enum"] as? [String] == [kind.rawValue])
        for key in ["recordSource", "recordFields", "editableFields"] {
          #expect(fields[key] == nil)
          let required = node["required"] as? [String] ?? []
          #expect(!required.contains(key))
        }
      }
      try check(try #require(definitions[kind.rawValue]))
    }
  }

  // Given nested references and a cycle, when extracted, then only the complete reference closure remains.
  @Test func nestedReferencesRetainReachableDefinitionsOnly() throws {
    var source = try object(layout())
    var definitions = try #require(source["$defs"] as? [String: [String: Any]])
    var chart = try #require(definitions["chart"])
    var fields = try #require(chart["properties"] as? [String: Any])
    fields["points"] = ["type": "array", "items": ["$ref": "#/$defs/Point"]]
    chart["properties"] = fields
    definitions["chart"] = chart
    definitions["Point"] = ["type": "object", "properties": ["icon": ["$ref": "#/$defs/Icon"], "next": ["$ref": "#/$defs/Point"]]]
    source["$defs"] = definitions
    let result = try object(NativeComponentLayout.componentSchema(from: data(source), kind: .chart, projected: true))
    let retained = try #require(result["$defs"] as? [String: [String: Any]])
    #expect(Set(retained.keys) == ["chart", "Point", "Icon"])
    let originalPoint = try #require(definitions["Point"])
    let originalIcon = try #require(definitions["Icon"])
    #expect(NSDictionary(dictionary: try #require(retained["Point"])).isEqual(to: originalPoint))
    #expect(NSDictionary(dictionary: try #require(retained["Icon"])).isEqual(to: originalIcon))
  }

  // Given an unsupported kind or invalid definition, when extracted, then schema generation rejects it.
  @Test func rejectsContainersMissingKindsAndInvalidReferences() throws {
    let source = try layout()
    for kind: UINode.Kind in [.vstack, .hstack, .grid, .section, .form, .button, .navigationLink] {
      #expect(throws: UIError.self) {
        try NativeComponentLayout.componentSchema(from: source, kind: kind, projected: false)
      }
    }
    for kind: UINode.Kind in [.text, .control] {
      #expect(throws: UIError.self) {
        try NativeComponentLayout.componentSchema(from: source, kind: kind, projected: true)
      }
    }
    var schema = try object(source)
    var definitions = try #require(schema["$defs"] as? [String: [String: Any]])
    let originalList = try #require(definitions["list"])
    for key in ["recordSource", "recordFields"] {
      var list = originalList
      var fields = try #require(list["properties"] as? [String: Any])
      fields.removeValue(forKey: key)
      list["properties"] = fields
      definitions["list"] = list
      schema["$defs"] = definitions
      #expect(throws: UIError.self) {
        try NativeComponentLayout.componentSchema(from: data(schema), kind: .list, projected: true)
      }
    }
    definitions.removeValue(forKey: "list")
    schema["$defs"] = definitions
    #expect(throws: UIError.self) {
      try NativeComponentLayout.componentSchema(from: data(schema), kind: .list, projected: false)
    }
    for invalid: [String: Any] in [
      ["type": "object", "properties": ["type": ["type": "string", "enum": ["chart", "list"]]]],
      ["type": "object", "properties": ["type": ["enum": ["list"]], "icon": ["$ref": "#/$defs/Missing"]]],
    ] {
      definitions["list"] = invalid
      schema["$defs"] = definitions
      #expect(throws: UIError.self) {
        try NativeComponentLayout.componentSchema(from: data(schema), kind: .list, projected: false)
      }
    }
    #expect(throws: UIError.self) {
      try NativeComponentLayout.componentSchema(from: Data("[]".utf8), kind: .list, projected: false)
    }
  }

  // Given one shared schema, when both modes are extracted, then the original schema remains unchanged.
  @Test func extractionDoesNotMutateOriginalSchema() throws {
    let source = try layout()
    let original = source
    let projected = try NativeComponentLayout.componentSchema(from: source, kind: .list, projected: true)
    _ = try NativeComponentLayout.componentSchema(from: source, kind: .list, projected: false)
    #expect(source == original)
    #expect(try NativeComponentLayout.componentSchema(from: source, kind: .list, projected: true) == projected)
    let definitions = try #require(try object(source)["$defs"] as? [String: [String: Any]])
    #expect(definitions["Node"] != nil)
    let originalRequired = definitions["list"]?["required"] as? [String] ?? []
    #expect(!originalRequired.contains("recordFields"))
  }
}
