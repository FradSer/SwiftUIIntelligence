import Foundation
import SwiftUIIntelligence
@_spi(Testing) @testable import SwiftUIIntelligenceFoundationModels
import Testing

@Suite struct NativeCalculationDataTests {
  private var signature: CalculationRegistry.Signature {
    .init(id: "scale", inputs: ["factor": .number], outputs: ["summary": .text],
      recordInputs: ["rows": .init(fields: ["name": .text, "amount": .number])],
      recordOutputs: ["result": .init(fields: ["name": .text])])
  }

  private func encode(_ object: [String: Any]) throws -> Data {
    try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
  }

  private func object(_ data: Data) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
  }

  private var authored: [String: Any] {
    ["state": [["id": "count", "kind": "number", "value": 2, "minimum": 0, "maximum": 100, "step": 1],
      ["id": "answer", "kind": "text", "value": "Unchanged"]],
      "recordInputs": ["scale": ["rows": ["id": "source", "schema": ["fields": ["name": "text", "amount": "number"]],
        "rows": [["id": "second", "values": ["name": "Exact / name", "amount": 1.2345678901234567]],
          ["id": "first", "values": ["name": "Other", "amount": 0]]]]]],
      "recordOutputs": ["scale": ["result": ["id": "destination"]]]]
  }

  private var binding: [String: Any] {
    ["id": "calculate", "capability": "scale", "inputs": ["factor": "count"],
      "outputs": ["summary": "answer"], "recordInputs": ["rows": "source"], "recordOutputs": ["result": "destination"]]
  }

  @Test func rejectsUnauthoredDefaultsNullsAndKindInapplicableFields() throws {
    for state: [[String: Any]] in [
      [["id": "count", "kind": "number", "value": 2]],
      [["id": "answer", "kind": "text", "value": "Unchanged", "minimum": NSNull()]],
      [["id": "answer", "kind": "text", "value": "Unchanged", "minimum": 0]],
      [["id": "choice", "kind": "choice", "value": "A"]],
    ] {
      var data = authored
      data["state"] = state
      #expect(throws: UIError.self) { try NativeCalculationData.normalizeData(encode(data), signatures: [signature]) }
    }
  }

  @Test func nativeSourceRecordsEnforceCodePointLimitsWithoutReferences() throws {
    for pairs in [500, 501] {
      var source = authored
      let text = String(repeating: "e\u{301}", count: pairs)
      source["recordInputs"] = ["scale": ["rows": ["id": "source", "schema": ["fields": ["name": "text", "amount": "number"]],
        "rows": [["id": "row", "values": ["name": text, "amount": 1]]]]]]
      if pairs == 500 {
        _ = try NativeCalculationData.normalizeData(encode(source), signatures: [signature])
      } else {
        #expect(throws: UIError.self) { try NativeCalculationData.normalizeData(encode(source), signatures: [signature]) }
      }
    }
  }

  @Test func bindingCountMatchesAuthoredCapabilitySlots() throws {
    let data = try NativeCalculationData.normalizeData(encode(authored), signatures: [signature])
    let schema = try object(NativeCalculationData.bindingSchema(data: data, signatures: [signature]))
    let fields = try #require(schema["properties"] as? [String: [String: Any]])
    #expect(fields["calculations"]?["minItems"] as? Int == 1)
    #expect(fields["calculations"]?["maxItems"] as? Int == 1)
    let duplicate = try encode(["calculations": [binding, binding.merging(["id": "second"]) { _, new in new }]])
    #expect(throws: UIError.self) { try NativeCalculationData.normalizeBindings(duplicate, data: data, signatures: [signature]) }
  }

  @Test func twoSlotsRejectTwoBindingsForOnlyOneCapability() throws {
    let other = CalculationRegistry.Signature(id: "other", inputs: ["value": .number], outputs: ["result": .number])
    var source = authored
    var inputs = try #require(source["recordInputs"] as? [String: Any])
    var outputs = try #require(source["recordOutputs"] as? [String: Any])
    inputs["other"] = [String: Any]()
    outputs["other"] = [String: Any]()
    source["recordInputs"] = inputs
    source["recordOutputs"] = outputs
    let accepted = try NativeCalculationData.normalizeData(encode(source), signatures: [signature, other])
    let duplicate = try encode(["calculations": [binding, binding.merging(["id": "second"]) { _, new in new }]])
    #expect(throws: UIError.self) { try NativeCalculationData.normalizeBindings(duplicate, data: accepted, signatures: [signature, other]) }
  }

  // Given registered slots, when guidance and normalization run, then every slot remains required.
  @Test func requiresEveryRegisteredSlotAndClosedRoot() throws {
    let finite = DocumentGenerationContract.schemaJSON(registeredCalculations: ["scale"], includeRecords: true)
    let schema = try object(NativeCalculationData.dataSchema(from: finite, signatures: [signature]))
    #expect(schema["additionalProperties"] as? Bool == false)
    #expect(schema["required"] as? [String] == ["recordInputs", "recordOutputs", "state"])
    let fields = try #require(schema["properties"] as? [String: Any])
    let finiteFields = try #require(object(finite)["properties"] as? [String: Any])
    #expect(NSDictionary(dictionary: try #require(fields["state"] as? [String: Any]))
      .isEqual(to: try #require(finiteFields["state"] as? [String: Any])))
    let inputs = try #require(fields["recordInputs"] as? [String: Any])
    let capabilities = try #require(inputs["properties"] as? [String: [String: Any]])
    #expect(capabilities["scale"]?["required"] as? [String] == ["rows"])
    var missing = authored
    missing["recordInputs"] = ["scale": [:]]
    #expect(throws: UIError.self) { try NativeCalculationData.normalizeData(encode(missing), signatures: [signature]) }
    missing["recordInputs"] = [:]
    #expect(throws: UIError.self) { try NativeCalculationData.normalizeData(encode(missing), signatures: [signature]) }
  }

  // Given complete authored collections, when normalized, then values and row order remain unchanged.
  @Test func preservesSourcesAndSeparatesOutputReservations() throws {
    let accepted = try NativeCalculationData.normalizeData(encode(authored), signatures: [signature])
    let declaration = try object(accepted.declarations)
    #expect(Set(declaration.keys) == ["state", "records"])
    #expect(accepted.outputIDs == ["scale": ["result": "destination"]])
    let inputs = try #require(authored["recordInputs"] as? [String: [String: [String: Any]]])
    let records = try #require(declaration["records"] as? [[String: Any]])
    #expect(records.count == 1)
    #expect(NSDictionary(dictionary: records[0]).isEqual(to: try #require(inputs["scale"]?["rows"])))
    #expect(NSArray(array: try #require(declaration["state"] as? [Any])).isEqual(to: try #require(authored["state"] as? [Any])))
    let extra = CalculationRegistry.Signature(id: "alpha", inputs: [:], outputs: [:],
      recordInputs: ["z": .init(fields: ["label": .text]), "a": .init(fields: ["label": .text])],
      recordOutputs: ["result": .init(fields: ["label": .text])])
    var multiple = authored
    var sourceMap = try #require(multiple["recordInputs"] as? [String: Any])
    sourceMap["alpha"] = ["z": ["id": "z-source", "schema": ["fields": ["label": "text"]], "rows": []],
      "a": ["id": "a-source", "schema": ["fields": ["label": "text"]], "rows": []]]
    multiple["recordInputs"] = sourceMap
    multiple["recordOutputs"] = ["scale": ["result": ["id": "destination"]], "alpha": ["result": ["id": "alpha-result"]]]
    let ordered = try NativeCalculationData.normalizeData(encode(multiple), signatures: [signature, extra])
    let orderedRecords = try #require(object(ordered.declarations)["records"] as? [[String: Any]])
    #expect(orderedRecords.compactMap { $0["id"] as? String } == ["a-source", "z-source", "source"])
  }

  // Given accepted data, when bindings run, then enums and validation use actual compatible IDs only.
  @Test func constrainsBindingsAndRejectsIncompatibleOrEmptyCandidates() throws {
    let accepted = try NativeCalculationData.normalizeData(encode(authored), signatures: [signature])
    let schema = try object(NativeCalculationData.bindingSchema(data: accepted, signatures: [signature]))
    let root = try #require(schema["properties"] as? [String: [String: Any]])
    let items = try #require(root["calculations"]?["items"] as? [String: Any])
    let variants = try #require(items["anyOf"] as? [[String: Any]])
    let fields = try #require(variants.first?["properties"] as? [String: [String: Any]])
    for (map, parameter, expected) in [("inputs", "factor", "count"), ("outputs", "summary", "answer"),
      ("recordInputs", "rows", "source"), ("recordOutputs", "result", "destination")] {
      let parameters = try #require(fields[map]?["properties"] as? [String: [String: Any]])
      #expect(parameters[parameter]?["enum"] as? [String] == [expected])
    }
    let result = try NativeCalculationData.normalizeBindings(encode(["calculations": [binding]]), data: accepted, signatures: [signature])
    #expect((try object(result)["calculations"] as? [Any])?.count == 1)
    var wrong = binding
    wrong["inputs"] = ["factor": "answer"]
    #expect(throws: UIError.self) { try NativeCalculationData.normalizeBindings(encode(["calculations": [wrong]]), data: accepted, signatures: [signature]) }
    wrong = binding; wrong["recordOutputs"] = ["result": "invented"]
    #expect(throws: UIError.self) { try NativeCalculationData.normalizeBindings(encode(["calculations": [wrong]]), data: accepted, signatures: [signature]) }
    var noNumbers = authored
    noNumbers["state"] = [["id": "answer", "kind": "text", "value": "Unchanged"]]
    let empty = try NativeCalculationData.normalizeData(encode(noNumbers), signatures: [signature])
    #expect(throws: UIError.self) { try NativeCalculationData.bindingSchema(data: empty, signatures: [signature]) }
    var omitted = binding
    omitted["inputs"] = [:]
    #expect(throws: UIError.self) { try NativeCalculationData.normalizeBindings(encode(["calculations": [omitted]]), data: accepted, signatures: [signature]) }
    var duplicate = binding
    duplicate["id"] = "second-binding"
    #expect(throws: UIError.self) { try NativeCalculationData.normalizeBindings(encode(["calculations": [binding, duplicate]]), data: accepted, signatures: [signature]) }
    let cyclicSignature = CalculationRegistry.Signature(id: "scale", inputs: ["factor": .number], outputs: ["summary": .number],
      recordInputs: signature.recordInputs, recordOutputs: signature.recordOutputs)
    var cyclic = binding
    cyclic["outputs"] = ["summary": "count"]
    #expect(throws: UIError.self) { try NativeCalculationData.normalizeBindings(encode(["calculations": [cyclic]]), data: accepted, signatures: [cyclicSignature]) }
    var badSchema = authored
    badSchema["recordInputs"] = ["scale": ["rows": ["id": "source", "schema": ["fields": ["name": "text"]], "rows": []]]]
    #expect(throws: UIError.self) { try NativeCalculationData.normalizeData(encode(badSchema), signatures: [signature]) }
  }

  // Given colliding IDs or too many reserved collections, when normalized, then no repair occurs.
  @Test func rejectsCollisionsAndCollectionLimit() throws {
    var collision = authored
    collision["recordOutputs"] = ["scale": ["result": ["id": "source"]]]
    #expect(throws: UIError.self) { try NativeCalculationData.normalizeData(encode(collision), signatures: [signature]) }
    var signatures: [CalculationRegistry.Signature] = []
    var sources: [String: Any] = [:]
    var destinations: [String: Any] = [:]
    for index in 0..<9 {
      let name = "cap\(index)"
      signatures.append(.init(id: name, inputs: [:], outputs: [:], recordInputs: ["rows": .init(fields: ["name": .text])],
        recordOutputs: ["result": .init(fields: ["name": .text])]))
      sources[name] = ["rows": ["id": "source\(index)", "schema": ["fields": ["name": "text"]], "rows": []]]
      destinations[name] = ["result": ["id": "destination\(index)"]]
    }
    #expect(throws: UIError.self) {
      try NativeCalculationData.normalizeData(encode(["state": [], "recordInputs": sources, "recordOutputs": destinations]), signatures: signatures)
    }
  }

  // Given missing, null, or invalid declarations, when normalized, then validation rejects them.
  @Test func rejectsMissingNullAndInvalidScalarState() throws {
    for key in ["state", "recordInputs", "recordOutputs"] {
      var invalid = authored
      invalid.removeValue(forKey: key)
      #expect(throws: UIError.self) { try NativeCalculationData.normalizeData(encode(invalid), signatures: [signature]) }
      invalid[key] = NSNull()
      #expect(throws: UIError.self) { try NativeCalculationData.normalizeData(encode(invalid), signatures: [signature]) }
    }
    var invalid = authored
    invalid["state"] = [["id": "bad", "kind": "number", "value": "not numeric"]]
    #expect(throws: (any Error).self) { try NativeCalculationData.normalizeData(encode(invalid), signatures: [signature]) }
    let accepted = try NativeCalculationData.normalizeData(encode(authored), signatures: [signature])
    for invalid in [[String: Any](), ["calculations": NSNull()], ["calculations": []]] {
      #expect(throws: UIError.self) { try NativeCalculationData.normalizeBindings(encode(invalid), data: accepted, signatures: [signature]) }
    }
  }
}
