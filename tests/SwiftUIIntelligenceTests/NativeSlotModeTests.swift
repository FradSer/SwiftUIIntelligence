import Foundation
import SwiftUIIntelligence
@testable import SwiftUIIntelligenceFoundationModels
import Testing

@Suite struct NativeSlotModeTests {
  private func data(_ value: Any) throws -> Data {
    try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
  }

  private func object(_ value: Data) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: value) as? [String: Any])
  }

  private func slot(_ id: String, kind: String, mode: String) -> [String: Any] {
    ["id": id, "type": "slot", "componentType": kind, "mode": mode, "purpose": "Present the authored \(kind) component."]
  }

  private func plan(_ root: [String: Any]) throws -> Data {
    try data(["version": 1, "root": root, "floatingActions": []])
  }

  // Given supported kinds, when the native schema is built, then each slot requires its permitted mode enum.
  @Test func schemaRequiresKindSpecificModeWithoutProjected() throws {
    let kinds: [UINode.Kind] = [.text, .control, .list, .table, .chart, .timeline]
    let native = try object(NativeLayoutSlots.nativePlanSchema(componentTypes: kinds, registeredActions: []))
    let original = try object(NativeLayoutSlots.planSchema(componentTypes: kinds, registeredActions: []))
    var definitions = try #require(native["$defs"] as? [String: [String: Any]])
    var branches = try #require(definitions["Slot"]?["anyOf"] as? [[String: Any]])
    for index in branches.indices {
      var fields = try #require(branches[index]["properties"] as? [String: [String: Any]])
      let kind = try #require((fields["componentType"]?["enum"] as? [String])?.first)
      #expect(fields["projected"] == nil)
      #expect(fields["mode"]?["type"] as? String == "string")
      #expect(fields["mode"]?["enum"] as? [String] == (["text", "control"].contains(kind) ? ["static"] : ["static", "records"]))
      let required = try #require(branches[index]["required"] as? [String])
      #expect(Set(required) == ["id", "type", "componentType", "mode", "purpose"])
      fields.removeValue(forKey: "purpose")
      fields.removeValue(forKey: "mode")
      fields["projected"] = ["type": "boolean", "enum": ["text", "control"].contains(kind) ? [false] : [false, true]]
      branches[index]["properties"] = fields
      branches[index]["required"] = required.filter { $0 != "purpose" }.map { $0 == "mode" ? "projected" : $0 }.sorted()
    }
    definitions["Slot"]?["anyOf"] = branches
    var restored = native
    restored["$defs"] = definitions
    #expect(NSDictionary(dictionary: restored).isEqual(to: original))
  }

  @Test func projectedRequirementAcceptsStaticSiblingButRejectsAllStatic() throws {
    for mode in ["records", "static"] {
      let root: [String: Any] = ["id": "group", "type": "vstack", "children": [
        slot("results", kind: "table", mode: mode), slot("reference", kind: "table", mode: "static")]]
      let normalized = try NativeLayoutSlots.normalizeNativePlan(plan(root))
      if mode == "records" {
        let accepted = try NativeLayoutSlots.validatePlan(normalized, requirements: .init(projectedComponents: [.table]))
        #expect(accepted.slots.map(\.projected) == [true, false])
      } else {
        #expect(throws: UIError.self) { try NativeLayoutSlots.validatePlan(normalized, requirements: .init(projectedComponents: [.table])) }
      }
    }
  }

  // Given model-authored modes, when normalized, then only the mode field changes and child order stays unchanged.
  @Test func normalizationPreservesTreeAndMapsModesInOrder() throws {
    let kinds = ["text", "control", "list", "table", "chart", "timeline"]
    let authored = kinds.enumerated().flatMap { index, kind in
      [slot("s\(index)", kind: kind, mode: "static")]
        + (["text", "control"].contains(kind) ? [] : [slot("r\(index)", kind: kind, mode: "records")])
    }.reversed()
    let children = Array(authored)
    let root: [String: Any] = ["id": "form", "type": "form", "title": "Authored title", "icon": "edit", "spacing": 0,
      "children": [["id": "section", "type": "section", "title": "Original section", "children": [
        ["id": "grid", "type": "grid", "columnCount": 3, "spacing": 7.5, "children": children]]]]]
    let source = try plan(root)
    let normalized = try NativeLayoutSlots.normalizeNativePlan(source)
    let validated = try NativeLayoutSlots.validatePlan(normalized)
    #expect(validated.slots.map(\.id) == children.compactMap { $0["id"] as? String })
    #expect(validated.slots.map(\.projected) == children.map { $0["mode"] as? String == "records" })
    var expected = root
    var sections = try #require(expected["children"] as? [[String: Any]])
    var grids = try #require(sections[0]["children"] as? [[String: Any]])
    grids[0]["children"] = children.map { child in
      var result = child
      result["projected"] = result.removeValue(forKey: "mode") as? String == "records"
      return result
    }
    sections[0]["children"] = grids
    expected["children"] = sections
    #expect(NSDictionary(dictionary: try object(normalized)).isEqual(to: try object(plan(expected))))
    #expect(try plan(root) == source)
  }

  // Given text or control records mode, when normalized, then existing kind validation rejects the plan.
  @Test func rejectsRecordsForTextAndControl() throws {
    for kind in ["text", "control"] {
      #expect(throws: UIError.self) {
        try NativeLayoutSlots.normalizeNativePlan(plan(slot("invalid", kind: kind, mode: "records")))
      }
    }
  }

  // Given an absent, ambiguous, or invalid mode, when normalized, then no default replaces the authored value.
  @Test func rejectsMissingNullUnknownAndBothProperties() throws {
    let valid = slot("answer", kind: "list", mode: "static")
    var missing = valid
    missing.removeValue(forKey: "mode")
    var legacy = missing
    legacy["projected"] = false
    var invalid = [missing, legacy]
    for mode: Any in [NSNull(), "unknown", "STATIC", true, 0, ["static"]] {
      var root = valid
      root["mode"] = mode
      invalid.append(root)
    }
    for projected: Any in [false, true, NSNull()] {
      var root = valid
      root["projected"] = projected
      invalid.append(root)
    }
    for root in invalid {
      #expect(throws: UIError.self) { try NativeLayoutSlots.normalizeNativePlan(plan(root)) }
    }
  }

  // Given invalid original grammar, when modes are normalized, then validation still rejects rather than repairs the plan.
  @Test func normalizationDoesNotInsertIDsOrRepairGrammar() throws {
    var missingID = slot("answer", kind: "text", mode: "static")
    missingID.removeValue(forKey: "id")
    var extra = slot("answer", kind: "text", mode: "static")
    extra["title"] = "Not allowed"
    for root: [String: Any] in [missingID, extra,
      ["id": "grid", "type": "grid", "children": []],
      ["id": "root", "type": "vstack", "children": [slot("same", kind: "text", mode: "static"), slot("same", kind: "list", mode: "records")]],
      ["id": "root", "type": "vstack", "children": [], "mode": "static"]] {
      #expect(throws: UIError.self) { try NativeLayoutSlots.normalizeNativePlan(plan(root)) }
    }
    for raw in ["null", "[]", "{\"version\":1,\"root\":{},\"floatingActions\":[]}"] {
      #expect(throws: UIError.self) { try NativeLayoutSlots.normalizeNativePlan(Data(raw.utf8)) }
    }
  }
}
