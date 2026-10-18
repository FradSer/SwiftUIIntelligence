import Foundation
import SwiftUIIntelligence
@_spi(Testing) @testable import SwiftUIIntelligenceFoundationModels
import Testing

@Suite struct NativeCorrelatedComponentSchemaTests {
  private let shared = RecordSchema(fields: ["name": .text, "amount": .number])

  private func declarations(_ schemas: [String: RecordSchema], output: String? = nil) throws -> Data {
    let records: [[String: Any]] = schemas.keys.sorted().map {
      ["id": $0, "schema": ["fields": schemas[$0]!.fields.mapValues(\.rawValue)], "rows": []]
    }
    let bindings = output.map { [CalculationBinding(id: "calculate", capability: "compute", inputs: [:],
      outputs: [:], recordOutputs: ["result": $0])] } ?? []
    let encoder = JSONEncoder()
    let recordsObject = records
    let bindingsObject = try JSONSerialization.jsonObject(with: encoder.encode(bindings))
    return try JSONSerialization.data(withJSONObject: ["state": [["id": "count", "kind": "number", "value": 1]], "records": recordsObject, "calculations": bindingsObject])
  }

  private func component(_ kind: UINode.Kind, declarations: Data,
    signatures: [CalculationRegistry.Signature] = []) throws -> Data {
    let layout = try NativeStagedSchema.layoutSchema(
      from: DocumentGenerationContract.schemaJSON(registeredCalculations: Set(signatures.map(\.id)).union(["compute"])),
      declarations: declarations, signatures: signatures)
    return try NativeComponentLayout.componentSchema(from: layout, kind: kind, projected: true)
  }

  private func variants(_ data: Data, kind: UINode.Kind) throws -> [[String: Any]] {
    #expect(try FoundationModelsDocumentProvider.validateNativeLayoutSchema(data))
    let root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(root["$ref"] as? String == "#/$defs/\(kind.rawValue)")
    let definitions = try #require(root["$defs"] as? [String: [String: Any]])
    return try #require(definitions[kind.rawValue]?["anyOf"] as? [[String: Any]])
  }

  private func fields(_ branch: [String: Any]) throws -> [String: [String: Any]] {
    try #require(branch["properties"] as? [String: [String: Any]])
  }

  private func itemEnum(_ field: [String: Any]?) throws -> [String] {
    try #require((field?["items"] as? [String: Any])?["enum"] as? [String])
  }

  // Given identical source and output fields, when correlated, then editing is source-only in every width branch.
  @Test func identicalSchemasKeepSourceEditingSeparateFromDerivedOutput() throws {
    let signatures = [CalculationRegistry.Signature(id: "compute", inputs: [:], outputs: [:], recordOutputs: ["result": shared])]
    let declared = try declarations(["source": shared], output: "derived")
    let input = try component(.table, declarations: declared, signatures: signatures)
    let result = try NativeCorrelatedComponentSchema.correlate(componentSchema: input,
      declarationsData: declared, selectedSignatures: signatures, kind: .table, projected: true)
    let branches = try variants(result, kind: .table)
    #expect(branches.count == 12)
    for branch in branches {
      let properties = try fields(branch)
      let source = try #require(properties["recordSource"]?["enum"] as? [String])
      #expect(source.count == 1)
      #expect(try itemEnum(properties["recordFields"]) == ["amount", "name"])
      #expect(Set(branch["required"] as? [String] ?? []).isSuperset(of: ["recordSource", "recordFields", "columns", "rows"]))
      if source == ["source"] {
        #expect(try itemEnum(properties["editableFields"]) == ["amount", "name"])
        #expect(properties["editableFields"]?["uniqueItems"] as? Bool == true)
      } else {
        #expect(source == ["derived"])
        #expect((properties["recordSource"]?["description"] as? String)?.contains("result") == true)
        #expect(properties["editableFields"] == nil)
        #expect(!(branch["required"] as? [String] ?? []).contains("editableFields"))
      }
      #expect(properties["recordSource"]?["const"] == nil)
      #expect(properties["recordFields"]?["minItems"] as? Int == properties["columns"]?["minItems"] as? Int)
      #expect(properties["recordFields"]?["maxItems"] as? Int == properties["columns"]?["maxItems"] as? Int)
      #expect(properties["columns"]?["maxItems"] as? Int == 2)
      #expect((properties["columns"]?["description"] as? String)?.contains("recordFields") == true)
      #expect((properties["recordFields"]?["description"] as? String)?.contains("columns") == true)
    }
  }

  // Given disjoint collections with no rows, when correlated, then field enums never cross collection boundaries.
  @Test func disjointSchemasUseExactCollectionFieldsAndRetainReferenceClosure() throws {
    let declared = try declarations(["first": shared, "second": RecordSchema(fields: ["enabled": .boolean])])
    let input = try component(.table, declarations: declared)
    let result = try NativeCorrelatedComponentSchema.correlate(componentSchema: input,
      declarationsData: declared, selectedSignatures: [], kind: .table, projected: true)
    for branch in try variants(result, kind: .table) {
      let properties = try fields(branch)
      let source = properties["recordSource"]?["enum"] as? [String]
      let expected = source == ["first"] ? ["amount", "name"] : ["enabled"]
      #expect(try itemEnum(properties["recordFields"]) == expected)
      #expect(try itemEnum(properties["editableFields"]) == expected)
    }
    // A non-projection grammar reference must remain reachable and unchanged.
    var root = try #require(JSONSerialization.jsonObject(with: component(.chart, declarations: declared)) as? [String: Any])
    var defs = try #require(root["$defs"] as? [String: [String: Any]])
    var chart = try #require(defs["chart"])
    var properties = try fields(chart)
    properties["points"] = ["type": "array", "items": ["$ref": "#/$defs/Point"]]
    chart["properties"] = properties
    defs["chart"] = chart
    defs["Point"] = ["type": "object", "properties": ["next": ["$ref": "#/$defs/Point"]]]
    root["$defs"] = defs
    let referenced = try JSONSerialization.data(withJSONObject: root)
    let correlated = try NativeCorrelatedComponentSchema.correlate(componentSchema: referenced,
      declarationsData: declared, selectedSignatures: [], kind: .chart, projected: true)
    let correlatedRoot = try #require(JSONSerialization.jsonObject(with: correlated) as? [String: Any])
    let retained = try #require(correlatedRoot["$defs"] as? [String: [String: Any]])
    #expect(NSDictionary(dictionary: try #require(retained["Point"])).isEqual(to: try #require(defs["Point"])))
  }

  // Given mixed primitive fields, when projected, then text projections allow repeated text and charts require text plus number.
  @Test func textEligibilityAndChartRuntimePositionalBoundary() throws {
    let declared = try declarations(["mixed": shared, "numeric": RecordSchema(fields: ["count": .number]),
      "text": RecordSchema(fields: ["title": .text])])
    for kind: UINode.Kind in [.list, .timeline, .chart] {
      let result = try NativeCorrelatedComponentSchema.correlate(componentSchema: component(kind, declarations: declared),
        declarationsData: declared, selectedSignatures: [], kind: kind, projected: true)
      let branches = try variants(result, kind: kind)
      #expect(branches.count == (kind == .chart ? 1 : 2))
      for branch in branches {
        let properties = try fields(branch)
        let source = properties["recordSource"]?["enum"] as? [String]
        #expect(source != ["numeric"])
        let projection = try #require(properties["recordFields"])
        #expect(projection["minItems"] as? Int == (kind == .list ? 1 : 3))
        #expect(projection["maxItems"] as? Int == (kind == .list ? 1 : 3))
        #expect(projection["prefixItems"] == nil)
        #expect(projection["uniqueItems"] as? Bool != true)
        if kind == .chart || kind == .timeline {
          #expect((projection["description"] as? String)?.contains("order") == true)
        }
        if kind == .chart {
          #expect((projection["description"] as? String)?.contains("amount") == true)
        }
        #expect(try itemEnum(projection) == (kind == .chart ? ["amount", "name"] : source == ["mixed"] ? ["name"] : ["title"]))
      }
    }
  }

  // Given static mode, when called with arbitrary bytes, then no decode or rewrite occurs.
  @Test func staticModeReturnsOriginalBytes() throws {
    let input = Data("  not a schema\n".utf8)
    #expect(try NativeCorrelatedComponentSchema.correlate(componentSchema: input,
      declarationsData: Data(), selectedSignatures: [], kind: .text, projected: false) == input)
  }

  // Given missing metadata or no suitable collection, when projected, then fail instead of inventing a binding.
  @Test func rejectsMissingSignaturesUnknownOutputsAndIneligibleCollections() throws {
    let signature = CalculationRegistry.Signature(id: "compute", inputs: [:], outputs: [:], recordOutputs: ["result": shared])
    let declared = try declarations(["source": shared], output: "derived")
    let input = try component(.table, declarations: declared, signatures: [signature])
    for signatures in [[], [CalculationRegistry.Signature(id: "compute", inputs: [:], outputs: [:])]] {
      #expect(throws: UIError.self) {
        try NativeCorrelatedComponentSchema.correlate(componentSchema: input,
          declarationsData: declared, selectedSignatures: signatures, kind: .table, projected: true)
      }
    }
    let numeric = try declarations(["numeric": RecordSchema(fields: ["amount": .number])])
    for kind: UINode.Kind in [.list, .timeline, .chart] {
      #expect(throws: UIError.self) {
        try NativeCorrelatedComponentSchema.correlate(componentSchema: input,
          declarationsData: numeric, selectedSignatures: [], kind: kind, projected: true)
      }
    }
  }
}
