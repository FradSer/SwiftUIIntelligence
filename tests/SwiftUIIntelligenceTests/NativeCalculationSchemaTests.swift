import Foundation
import SwiftUIIntelligence
@_spi(Testing) import SwiftUIIntelligenceFoundationModels
import Testing

@Test func recordIdentityGuidanceDoesNotRequireLayoutNodeKinds() throws {
  let schema = Data(#"{"type":"object","additionalProperties":false,"properties":{"id":{"type":"string"}},"required":["id"]}"#.utf8)
  let debug = try FoundationModelsDocumentProvider.nativeSchemaDescription(schema)
  #expect(!debug.contains("metric"))
  #expect(!debug.contains("grid"))
  #expect(debug.contains("identifier"))
}

@Suite struct NativeCalculationSchemaTests {
  private func objects(_ value: Any) -> [[String: Any]] {
    if let object = value as? [String: Any] {
      return [object] + object.values.flatMap(objects)
    }
    if let array = value as? [Any] { return array.flatMap(objects) }
    return []
  }

  private func schema(_ request: DocumentGenerationRequest) throws -> [[String: Any]] {
    let native = try FoundationModelsDocumentProvider.generationSchema(for: request)
    return objects(try JSONSerialization.jsonObject(with: JSONEncoder().encode(native)))
  }

  private func maps(_ objects: [[String: Any]], keys: Set<String>) -> [[String: Any]] {
    objects.filter { object in
      guard let properties = object["properties"] as? [String: Any] else { return false }
      return Set(properties.keys) == keys
    }
  }

  // Given two scalar capabilities, when encoded, then each variant has exact closed parameter maps.
  @Test func scalarParametersUseClosedCapabilityVariants() throws {
    let request = try DocumentGenerationRequest(messages: [.init(role: .user, content: "Calculate the supplied values.")], calculationSignatures: [
      .init(id: "scale", inputs: ["amount": .number, "enabled": .boolean], outputs: ["total": .number]),
      .init(id: "describe", inputs: ["name": .text], outputs: ["summary": .text]),
    ])
    let encoded = try schema(request)
    for keys: Set<String> in [["amount", "enabled"], ["total"], ["name"], ["summary"]] {
      let matches = maps(encoded, keys: keys)
      #expect(!matches.isEmpty)
      #expect(matches.allSatisfy { ($0["additionalProperties"] as? Bool) == false })
      #expect(matches.allSatisfy { Set($0["required"] as? [String] ?? []) == keys })
    }
    #expect(encoded.contains { ($0["enum"] as? [String]) == ["scale"] })
    #expect(encoded.contains { ($0["enum"] as? [String]) == ["describe"] })
    #expect(encoded.contains { ($0["anyOf"] as? [Any])?.count == 2 })
  }

  // Given record-only output, when encoded, then empty scalar maps and all projections remain available.
  @Test func recordOnlyCapabilityKeepsEmptyMapsAndProjections() throws {
    let request = try DocumentGenerationRequest(messages: [.init(role: .user, content: "Show the computed rows.")], calculationSignatures: [
      .init(id: "rows", inputs: [:], outputs: [:], recordOutputs: ["entries": .init(fields: ["label": .text, "value": .number, "series": .text])]),
    ])
    let encoded = try schema(request)
    #expect(!maps(encoded, keys: ["entries"]).isEmpty)
    #expect(maps(encoded, keys: []).count >= 2)
    for kind in ["table", "list", "chart"] {
      let variants = encoded.filter { object in
        guard let properties = object["properties"] as? [String: [String: Any]] else { return false }
        return (properties["type"]?["enum"] as? [String]) == [kind]
      }
      #expect(!variants.isEmpty)
      #expect(variants.allSatisfy { object in
        let fields = object["properties"] as? [String: Any]
        return fields?["recordSource"] != nil && fields?["recordFields"] != nil
      })
    }
  }

  // Given one numeric control and derived text/boolean values, then all state kinds and 32 slots remain available.
  @Test func controlsDoNotNarrowDerivedStateOrReplaceTheArray() throws {
    let request = try DocumentGenerationRequest(messages: [.init(role: .user, content: "Edit the amount and show the computed result.")], calculationSignatures: [
      .init(id: "compute", inputs: ["amount": .number], outputs: ["summary": .text, "ready": .boolean]),
    ], requirements: .init(components: [.control, .text], controls: [.stepper]))
    let encoded = try schema(request)
    let states = encoded.compactMap { ($0["properties"] as? [String: [String: Any]])?["state"] }
    #expect(!states.isEmpty)
    #expect(states.allSatisfy { ($0["type"] as? String) == "array" && ($0["maxItems"] as? Int) == 32 })
    for kind in ["text", "number", "boolean", "choice", "date"] {
      #expect(encoded.contains { ($0["enum"] as? [String]) == [kind] })
    }
  }

  private func resolved(_ value: [String: Any], in root: [String: Any]) throws -> [String: Any] {
    guard let reference = value["$ref"] as? String else { return value }
    let definitions = try #require(root["$defs"] as? [String: [String: Any]])
    return try #require(definitions[String(reference.split(separator: "/").last!)])
  }

  private func fields(_ value: [String: Any], in root: [String: Any]) throws -> [String: [String: Any]] {
    try #require(resolved(value, in: root)["properties"] as? [String: [String: Any]])
  }

  // Authorized support replaces the former rejection: finite declarations preserve exact registered field kinds.
  @Test func recordInputsProduceFiniteTypedDeclarationsAndExactMaps() throws {
    let rowSchema = RecordSchema(fields: ["label": .text, "amount": .number, "selected": .boolean])
    let request = try DocumentGenerationRequest(messages: [.init(role: .user, content: "Calculate the supplied rows.")], calculationSignatures: [
      .init(id: "sum", inputs: [:], outputs: ["total": .number], recordInputs: ["items": rowSchema]),
      .init(id: "count", inputs: [:], outputs: ["count": .number], recordInputs: ["source": rowSchema]),
      .init(id: "describe", inputs: [:], outputs: ["text": .text], recordInputs: ["names": .init(fields: ["name": .text])]),
    ])
    let native = try FoundationModelsDocumentProvider.generationSchema(for: request)
    let root = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(native)) as? [String: Any])
    let properties = try fields(root, in: root)
    let records = try #require(properties["records"])
    #expect(records["type"] as? String == "array")
    #expect(records["maxItems"] as? Int == 16)
    // Selected record-input capabilities require source declarations; empty collections still use rows: [].
    #expect((root["required"] as? [String] ?? []).contains("records"))
    let item = try resolved(#require(records["items"] as? [String: Any]), in: root)
    let variants = try #require(item["anyOf"] as? [[String: Any]])
    #expect(variants.count == 2)
    var observed: [Set<String>] = []
    for reference in variants {
      let collection = try resolved(reference, in: root)
      let collectionFields = try fields(collection, in: root)
      #expect(Set(collectionFields.keys) == ["id", "schema", "rows"])
      #expect(collection["additionalProperties"] as? Bool == false)
      #expect(collectionFields["id"]?["enum"] == nil)
      let declaration = try fields(#require(collectionFields["schema"]), in: root)
      let fieldMap = try resolved(#require(declaration["fields"]), in: root)
      let declaredFields = try fields(fieldMap, in: root)
      #expect(fieldMap["additionalProperties"] as? Bool == false)
      #expect(Set(fieldMap["required"] as? [String] ?? []) == Set(declaredFields.keys))
      observed.append(Set(declaredFields.keys))
      let rows = try #require(collectionFields["rows"])
      #expect(rows["type"] as? String == "array")
      #expect(rows["maxItems"] as? Int == 32)
      let row = try fields(#require(rows["items"] as? [String: Any]), in: root)
      #expect(Set(row.keys) == ["id", "values"])
      let valuesObject = try resolved(#require(row["values"]), in: root)
      let values = try fields(valuesObject, in: root)
      #expect(valuesObject["additionalProperties"] as? Bool == false)
      #expect(Set(values.keys) == Set(declaredFields.keys))
      #expect(Set(valuesObject["required"] as? [String] ?? []) == Set(values.keys))
      for (name, declaration) in declaredFields {
        let kind = try #require((declaration["enum"] as? [String])?.first)
        let expectedKind = name == "amount" ? "number" : name == "selected" ? "boolean" : "text"
        #expect(kind == expectedKind)
        // RecordSchema uses text; JSON Schema uses string for the same primitive.
        #expect(values[name]?["type"] as? String == (kind == "text" ? "string" : kind))
        if kind == "number" {
          #expect(values[name]?["minimum"] as? Double == -1e9)
          #expect(values[name]?["maximum"] as? Double == 1e9)
        }
      }
    }
    #expect(Set(observed) == [Set(["label", "amount", "selected"]), Set(["name"])])
    let calculations = try #require(properties["calculations"])
    let bindingItem = try resolved(#require(calculations["items"] as? [String: Any]), in: root)
    for reference in try #require(bindingItem["anyOf"] as? [[String: Any]]) {
      let binding = try resolved(reference, in: root)
      let bindingFields = try fields(binding, in: root)
      let capability = try #require((bindingFields["capability"]?["enum"] as? [String])?.first)
      let expected: Set<String> = [capability == "sum" ? "items" : capability == "count" ? "source" : "names"]
      let inputMap = try resolved(#require(bindingFields["recordInputs"]), in: root)
      #expect(Set(try fields(inputMap, in: root).keys) == expected)
      #expect(Set(inputMap["required"] as? [String] ?? []) == expected)
      #expect(inputMap["additionalProperties"] as? Bool == false)
      #expect((binding["required"] as? [String] ?? []).contains("recordInputs"))
    }
    let encoded = objects(root)
    let tables = encoded.filter { (($0["properties"] as? [String: [String: Any]])?["type"]?["enum"] as? [String]) == ["table"] }
    #expect(!tables.isEmpty)
    #expect(tables.allSatisfy { ($0["properties"] as? [String: Any])?["editableFields"] != nil })
  }

  @Test func outputOnlySignaturesDoNotDeclareSourceRecords() throws {
    let request = try DocumentGenerationRequest(messages: [.init(role: .user, content: "Calculate.")], calculationSignatures: [
      .init(id: "compute", inputs: [:], outputs: ["total": .number]),
    ])
    let encoded = try schema(request)
    #expect(encoded.allSatisfy { ($0["properties"] as? [String: Any])?["records"] == nil })
  }

  @Test func invalidRecordInputSchemaIsRejectedBeforeNativeConversion() {
    #expect(throws: UIError.self) {
      let request = try DocumentGenerationRequest(messages: [.init(role: .user, content: "Calculate.")], calculationSignatures: [
        .init(id: "compute", inputs: [:], outputs: ["total": .number], recordInputs: ["items": .init(fields: [:])]),
      ])
      _ = try FoundationModelsDocumentProvider.generationSchema(for: request)
    }
  }

  // Given an authorized ID without a signature, then native schema construction fails explicitly.
  @Test func missingSignatureIsRejected() throws {
    let request = try DocumentGenerationRequest(messages: [.init(role: .user, content: "Calculate.")], registeredCalculations: ["missing"])
    #expect(throws: UIError.self) { try FoundationModelsDocumentProvider.generationSchema(for: request) }
  }
}
