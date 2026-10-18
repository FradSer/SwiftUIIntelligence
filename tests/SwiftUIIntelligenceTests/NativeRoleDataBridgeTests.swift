import Foundation
import SwiftUIIntelligence
@_spi(Testing) @testable import SwiftUIIntelligenceFoundationModels
import Testing

@Suite struct NativeRoleDataBridgeTests {
  private var signature: CalculationRegistry.Signature {
    .init(id: "compare", inputs: ["first": .number, "second": .number, "when": .instant], outputs: ["summary": .text],
      recordInputs: ["people": .init(fields: ["name": .text])],
      recordOutputs: ["result": .init(fields: ["name": .text])])
  }

  private func encode(_ value: Any) throws -> Data {
    try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
  }

  private func object(_ data: Data) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
  }

  private var source: [String: Any] {
    ["scalarRoles": ["compare": ["inputs": [
      "first": ["id": "alice", "kind": "number", "value": 7.125, "minimum": -10, "maximum": 100, "step": 0.125],
      "second": ["id": "bob", "kind": "number", "value": 7.125, "minimum": -10, "maximum": 100, "step": 0.125],
      "when": ["id": "visit", "kind": "date", "value": "2026-06-01T12:34:56Z"]],
      "outputs": ["summary": ["id": "answer", "kind": "text", "value": "Not calculated"]]]],
      "recordInputs": ["compare": ["people": ["id": "people", "schema": ["fields": ["name": "text"]],
        "rows": [["id": "bob-row", "values": ["name": "Bob"]], ["id": "alice-row", "values": ["name": "Alice"]]]]]],
      "recordOutputs": ["compare": ["result": ["id": "result"]]]]
  }

  private var binding: [String: Any] {
    ["id": "compare-people", "capability": "compare", "inputs": ["first": "alice", "second": "bob", "when": "visit"],
      "outputs": ["summary": "answer"], "recordInputs": ["people": "people"], "recordOutputs": ["result": "result"]]
  }

  private func scalarEnums(_ data: AcceptedCalculationData) throws -> [String: [String]] {
    let schema = try object(NativeCalculationData.bindingSchema(data: data, signatures: [signature]))
    let root = try #require(schema["properties"] as? [String: [String: Any]])
    let items = try #require(root["calculations"]?["items"] as? [String: Any])
    let variants = try #require(items["anyOf"] as? [[String: Any]])
    let fields = try #require(variants.first?["properties"] as? [String: [String: Any]])
    let inputs = try #require(fields["inputs"]?["properties"] as? [String: [String: Any]])
    return try inputs.mapValues { try #require($0["enum"] as? [String]) }
  }

  // Given role declarations, when bridged, then equal values retain distinct roles and exact authored objects.
  @Test func preservesPeopleInstantAndRecordSlotsWithoutDefaults() throws {
    let roles = try #require(source["scalarRoles"] as? [String: Any])
    let expected = try NativeScalarRoles.normalizeRoles(encode(["declarations": roles]), signatures: [signature])
    let accepted = try NativeCalculationData.normalizeRoleData(encode(source), signatures: [signature])
    let declarations = try object(accepted.declarations)
    #expect(try encode(try #require(declarations["state"])) == expected.stateArrayData)
    #expect(accepted.scalarRoles == expected.roles)
    #expect(accepted.scalarRoles["compare"]?["inputs"] == ["first": "alice", "second": "bob", "when": "visit"])
    #expect(accepted.outputIDs == ["compare": ["result": "result"]])
    #expect(Set(declarations.keys) == ["state", "records"])
    let records = try #require(declarations["records"] as? [[String: Any]])
    let maps = try #require(source["recordInputs"] as? [String: [String: Any]])
    #expect(try encode(records[0]) == encode(try #require(maps["compare"]?["people"])))
    let result = try NativeCalculationData.normalizeBindings(encode(["calculations": [binding]]), data: accepted, signatures: [signature])
    #expect(try encode(try #require(object(result)["calculations"])) == encode([binding]))
  }

  // Given selected signatures, when schema is built, then scalar roles replace state and retain record slots.
  @Test func schemaUsesOnlySelectedRolesAndAllowedKinds() throws {
    let finite = DocumentGenerationContract.schemaJSON(registeredCalculations: ["compare"], includeRecords: true)
    let schema = try object(NativeCalculationData.roleDataSchema(from: finite, signatures: [signature]))
    #expect(schema["required"] as? [String] == ["recordInputs", "recordOutputs", "scalarRoles"])
    #expect(schema["additionalProperties"] as? Bool == false)
    let fields = try #require(schema["properties"] as? [String: Any])
    let roleSchema = try object(NativeScalarRoles.roleSchema(signatures: [signature]))
    let roleFields = try #require(roleSchema["properties"] as? [String: Any])
    #expect(try encode(try #require(fields["scalarRoles"])) == encode(try #require(roleFields["declarations"])))
    let legacy = try object(NativeCalculationData.dataSchema(from: finite, signatures: [signature]))
    let legacyFields = try #require(legacy["properties"] as? [String: Any])
    for key in ["recordInputs", "recordOutputs"] {
      #expect(try encode(try #require(fields[key])) == encode(try #require(legacyFields[key])))
    }
    #expect(throws: UIError.self) {
      try NativeCalculationData.roleDataSchema(from: finite, signatures: [signature], allowedKinds: [.number, .text])
    }
  }

  // Given authored roles, when explicit maps swap compatible IDs or omit entries, then normalization rejects them.
  @Test func singletonEnumsRejectWrongRolesAndMissingMaps() throws {
    let accepted = try NativeCalculationData.normalizeRoleData(encode(source), signatures: [signature])
    #expect(try scalarEnums(accepted) == ["first": ["alice"], "second": ["bob"], "when": ["visit"]])
    for inputs in [["first": "bob", "second": "alice", "when": "visit"], ["first": "alice", "when": "visit"]] {
      var wrong = binding
      wrong["inputs"] = inputs
      #expect(throws: UIError.self) {
        try NativeCalculationData.normalizeBindings(encode(["calculations": [wrong]]), data: accepted, signatures: [signature])
      }
    }
    var wrong = binding
    wrong["outputs"] = ["summary": "visit"] // A date is compatible with text, but is not this output role.
    #expect(throws: UIError.self) {
      try NativeCalculationData.normalizeBindings(encode(["calculations": [wrong]]), data: accepted, signatures: [signature])
    }
    var missing = source
    missing["recordInputs"] = ["compare": [:]]
    #expect(throws: UIError.self) { try NativeCalculationData.normalizeRoleData(encode(missing), signatures: [signature]) }
    missing = source
    missing["state"] = []
    #expect(throws: UIError.self) { try NativeCalculationData.normalizeRoleData(encode(missing), signatures: [signature]) }
  }

  // Given a shared input/output reference, when explicit maps form a cycle, then core validation still rejects it.
  @Test func sharedReferencesDoNotBypassCycles() throws {
    let cyclic = CalculationRegistry.Signature(id: "echo", inputs: ["value": .number], outputs: ["result": .number])
    let source: [String: Any] = ["scalarRoles": ["echo": [
      "inputs": ["value": ["id": "shared", "kind": "number", "value": 2, "minimum": 0, "maximum": 10, "step": 1]],
      "outputs": ["result": ["reference": "shared"]]]], "recordInputs": ["echo": [:]], "recordOutputs": ["echo": [:]]]
    let accepted = try NativeCalculationData.normalizeRoleData(encode(source), signatures: [cyclic])
    _ = try NativeCalculationData.bindingSchema(data: accepted, signatures: [cyclic])
    let binding: [String: Any] = ["id": "cycle", "capability": "echo", "inputs": ["value": "shared"],
      "outputs": ["result": "shared"], "recordInputs": [:], "recordOutputs": [:]]
    #expect(throws: UIError.self) {
      try NativeCalculationData.normalizeBindings(encode(["calculations": [binding]]), data: accepted, signatures: [cyclic])
    }
  }

  // Given an explicit shared reference, when accepted, then roles share the authored ID without synthesizing maps.
  @Test func sharedReferencesAndLegacyCompatibility() throws {
    var shared = source
    var roles = try #require(shared["scalarRoles"] as? [String: [String: [String: Any]]])
    roles["compare"]?["inputs"]?["second"] = ["reference": "alice"]
    shared["scalarRoles"] = roles
    let accepted = try NativeCalculationData.normalizeRoleData(encode(shared), signatures: [signature])
    #expect(try scalarEnums(accepted)["second"] == ["alice"])
    var mapped = binding
    mapped["inputs"] = ["first": "alice", "second": "alice", "when": "visit"]
    _ = try NativeCalculationData.normalizeBindings(encode(["calculations": [mapped]]), data: accepted, signatures: [signature])
    let original = try NativeCalculationData.normalizeRoleData(encode(source), signatures: [signature])
    var legacy = source
    legacy.removeValue(forKey: "scalarRoles")
    legacy["state"] = try object(original.declarations)["state"]
    let old = try NativeCalculationData.normalizeData(encode(legacy), signatures: [signature])
    #expect(old.scalarRoles.isEmpty)
    #expect(old.declarations == original.declarations)
    #expect(try scalarEnums(old)["first"] == ["alice", "bob"])
    let initialized = AcceptedCalculationData(declarations: old.declarations, outputIDs: old.outputIDs)
    #expect(initialized.scalarRoles.isEmpty)
  }
}
