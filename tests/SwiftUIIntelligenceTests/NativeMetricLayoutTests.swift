import Foundation
import SwiftUIIntelligence
@testable import SwiftUIIntelligenceFoundationModels
import Testing

@Suite struct NativeMetricLayoutTests {
  private func data(_ value: Any) throws -> Data {
    try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
  }

  private func object(_ value: Data) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: value) as? [String: Any])
  }

  private func layout(state: [[String: Any]]) throws -> Data {
    try NativeStagedSchema.layoutSchema(
      from: DocumentGenerationContract.schemaJSON(componentTypes: ["metric"], registeredCalculations: ["compute"]),
      declarations: data(["state": state, "calculations": []]))
  }

  private func metric(_ schema: Data) throws -> [String: Any] {
    let definitions = try #require(try object(schema)["$defs"] as? [String: [String: Any]])
    return try #require(definitions["metric"])
  }

  // Given a numeric state, when a static metric schema is extracted, then its display fields and icon closure remain.
  @Test func staticExtractionPreservesDisplayFieldsAndIconClosure() throws {
    let source = try layout(state: [["id": "total", "kind": "number", "value": 12]])
    let extracted = try NativeComponentLayout.componentSchema(from: source, kind: .metric, projected: false)
    let result = try object(extracted)
    #expect(result["$ref"] as? String == "#/$defs/metric")
    let definitions = try #require(result["$defs"] as? [String: [String: Any]])
    #expect(Set(definitions.keys) == ["metric", "Icon"])
    let original = try metric(source)
    #expect(NSDictionary(dictionary: try metric(extracted)).isEqual(to: original))
    let fields = try #require(original["properties"] as? [String: [String: Any]])
    #expect(fields["valueBinding"]?["enum"] as? [String] == ["total"])
    #expect(Set(original["required"] as? [String] ?? []).isSuperset(of: ["value", "label", "detail", "icon"]))
    #expect(!(original["required"] as? [String] ?? []).contains("valueBinding"))
    for key in ["recordSource", "recordFields", "editableFields"] { #expect(fields[key] == nil) }
    #expect(throws: UIError.self) {
      try NativeComponentLayout.componentSchema(from: source, kind: .metric, projected: true)
    }
  }

  // Given a metric slot, when either schema is built, then only static mode is available.
  @Test func metricSlotSchemasPermitStaticOnly() throws {
    for native in [false, true] {
      let schema = try object(native
        ? NativeLayoutSlots.nativePlanSchema(componentTypes: [.metric], registeredActions: [])
        : NativeLayoutSlots.planSchema(componentTypes: [.metric], registeredActions: []))
      let definitions = try #require(schema["$defs"] as? [String: [String: Any]])
      let branches = try #require(definitions["Slot"]?["anyOf"] as? [[String: Any]])
      #expect(branches.count == 1)
      let fields = try #require(branches[0]["properties"] as? [String: [String: Any]])
      #expect(fields["componentType"]?["enum"] as? [String] == ["metric"])
      if native {
        #expect(fields["mode"]?["enum"] as? [String] == ["static"])
        #expect((branches[0]["required"] as? [String] ?? []).contains("purpose"))
      } else { #expect(fields["projected"]?["enum"] as? [Bool] == [false]) }
    }
  }

  // Given an authored metric purpose, when normalized and assembled, then only mode changes and the scalar binding survives.
  @Test func normalizationAndAssemblyPreserveScalarBinding() throws {
    let purpose = "Display the exact numeric total."
    let slot: [String: Any] = ["id": "total", "type": "slot", "componentType": "metric", "mode": "static", "purpose": purpose]
    let plan = try data(["version": 1, "root": slot, "floatingActions": []])
    let normalized = try NativeLayoutSlots.normalizeNativePlan(plan)
    #expect(try NativeLayoutSlots.validatePlan(normalized).slots == [.init(id: "total", componentType: .metric, projected: false, purpose: purpose)])
    let component: [String: Any] = ["id": "total", "type": "metric", "label": "Total", "value": "12", "detail": "Supplied", "icon": "people", "valueBinding": "amount"]
    let assembled = try NativeLayoutSlots.assemble(plan: normalized, components: ["total": data(component)])
    #expect(NSDictionary(dictionary: try #require(try object(assembled)["root"] as? [String: Any])).isEqual(to: component))
    var projected = slot
    projected["mode"] = "records"
    #expect(throws: UIError.self) {
      try NativeLayoutSlots.normalizeNativePlan(data(["version": 1, "root": projected, "floatingActions": []]))
    }
  }

  // Given mixed scalar kinds, when scoped, then metric bindings contain exactly the authored numeric IDs.
  @Test func valueBindingUsesExactNumericIDs() throws {
    let scoped = try layout(state: [
      ["id": "zTotal", "kind": "number", "value": 12],
      ["id": "aInput", "kind": "number", "value": 2],
      ["id": "caption", "kind": "text", "value": "Total"],
      ["id": "enabled", "kind": "toggle", "value": true],
    ])
    let fields = try #require(try metric(scoped)["properties"] as? [String: [String: Any]])
    #expect(fields["valueBinding"]?["type"] as? String == "string")
    #expect(fields["valueBinding"]?["enum"] as? [String] == ["aInput", "zTotal"])
  }

  // Given no numeric state, when scoped and assembled, then static metric data stays unchanged without a binding.
  @Test func noNumericStateRetainsStaticMetricContract() throws {
    for state: [[String: Any]] in [[], [["id": "caption", "kind": "text", "value": "Total"]]] {
      let scoped = try layout(state: state)
      let extracted = try NativeComponentLayout.componentSchema(from: scoped, kind: .metric, projected: false)
      let definition = try metric(extracted)
      let fields = try #require(definition["properties"] as? [String: [String: Any]])
      #expect(fields["valueBinding"] == nil)
      #expect((definition["required"] as? [String] ?? []).contains("value"))
      #expect(!(definition["required"] as? [String] ?? []).contains("valueBinding"))
    }
    let plan = try data(["version": 1, "root": ["id": "total", "type": "slot", "componentType": "metric", "projected": false], "floatingActions": []])
    let component: [String: Any] = ["id": "total", "type": "metric", "label": "Total", "value": "12 people", "detail": "Supplied", "icon": "people"]
    let assembled = try NativeLayoutSlots.assemble(plan: plan, components: ["total": data(component)])
    #expect(NSDictionary(dictionary: try #require(try object(assembled)["root"] as? [String: Any])).isEqual(to: component))
  }
}
