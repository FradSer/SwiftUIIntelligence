import Foundation
import SwiftUIIntelligence
@testable import SwiftUIIntelligenceFoundationModels
import Testing

@Suite struct NativeSlotPurposeTests {
  private func data(_ value: Any) throws -> Data {
    try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
  }

  private func object(_ value: Data) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: value) as? [String: Any])
  }

  private func slot(_ id: String = "answer", purpose: Any = "Explain the result.") -> [String: Any] {
    ["id": id, "type": "slot", "componentType": "text", "mode": "static", "purpose": purpose]
  }

  private func plan(_ root: [String: Any]) throws -> Data {
    try data(["version": 1, "root": root, "floatingActions": []])
  }

  // Given supported kinds, when the native schema is built, then only slot variants require bounded purpose text.
  @Test func nativeSchemaRequiresPurposeOnlyOnSlots() throws {
    let kinds: [UINode.Kind] = [.text, .control, .list, .table, .chart, .timeline]
    let schema = try object(NativeLayoutSlots.nativePlanSchema(componentTypes: kinds, registeredActions: []))
    let definitions = try #require(schema["$defs"] as? [String: [String: Any]])
    let slots = try #require(definitions["Slot"]?["anyOf"] as? [[String: Any]])
    #expect(slots.count == kinds.count)
    for branch in slots {
      let fields = try #require(branch["properties"] as? [String: [String: Any]])
      #expect(fields["purpose"]?["type"] as? String == "string")
      #expect(fields["purpose"]?["minLength"] as? Int == 1)
      #expect(fields["purpose"]?["maxLength"] as? Int == 500)
      #expect((branch["required"] as? [String])?.contains("purpose") == true)
    }
    let nodes = try #require(definitions["Node"]?["anyOf"] as? [[String: Any]])
    for branch in nodes.dropFirst() {
      #expect((branch["properties"] as? [String: Any])?["purpose"] == nil)
      #expect((branch["required"] as? [String])?.contains("purpose") == false)
    }
  }

  // Given missing or invalid purpose text, when native and internal plans are checked, then no default repairs it.
  @Test func rejectsMissingAndInvalidNativePurposeAndInvalidInternalPurpose() throws {
    var missing = slot()
    missing.removeValue(forKey: "purpose")
    #expect(throws: UIError.self) { try NativeLayoutSlots.normalizeNativePlan(plan(missing)) }
    for purpose: Any in ["", " \n\t", NSNull(), true, 42, ["purpose"], String(repeating: "a", count: 501)] {
      let native = slot(purpose: purpose)
      #expect(throws: UIError.self) { try NativeLayoutSlots.normalizeNativePlan(plan(native)) }
      var internalSlot = native
      internalSlot.removeValue(forKey: "mode")
      internalSlot["projected"] = false
      #expect(throws: UIError.self) { try NativeLayoutSlots.validatePlan(plan(internalSlot)) }
    }
  }

  @Test func purposeLimitCountsUnicodeScalarsWithoutNormalizingText() throws {
    let boundary = String(repeating: "e\u{301}", count: 250)
    let accepted = try NativeLayoutSlots.normalizeNativePlan(plan(slot(purpose: boundary)))
    #expect(try NativeLayoutSlots.validatePlan(accepted).slots.first?.purpose?.unicodeScalars.count == 500)
    for text in [String(repeating: "e\u{301}", count: 251), "e" + String(repeating: "\u{301}", count: 500)] {
      #expect(throws: UIError.self) { try NativeLayoutSlots.normalizeNativePlan(plan(slot(purpose: text))) }
    }
  }

  // Given authored whitespace, Unicode, and boundary lengths, when normalized, then values and slot order stay exact.
  @Test func preservesAuthoredPurposeBytesAndOrder() throws {
    let purposes = ["  Explain e\u{301} and 中文.\n", "x", String(repeating: "a", count: 500)]
    let children = purposes.enumerated().map { slot("s\($0.offset)", purpose: $0.element) }
    let normalized = try NativeLayoutSlots.normalizeNativePlan(plan(["id": "root", "type": "vstack", "spacing": 7.5, "children": children]))
    let validated = try NativeLayoutSlots.validatePlan(normalized)
    #expect(validated.slots.map(\.id) == ["s0", "s1", "s2"])
    #expect(validated.slots.map { $0.purpose.map { Array($0.utf8) } } == purposes.map { Optional(Array($0.utf8)) })
    let root = try #require(try object(normalized)["root"] as? [String: Any])
    #expect(root["spacing"] as? Double == 7.5)
    let normalizedChildren = try #require(root["children"] as? [[String: Any]])
    #expect(normalizedChildren.compactMap { ($0["purpose"] as? String).map { Array($0.utf8) } } == purposes.map { Array($0.utf8) })
    #expect(validated.planData == normalized)
  }

  // Given a legacy boolean plan, when validated, then purpose remains optional and the old initializer still works.
  @Test func legacyInternalPlanAndSlotInitializerRemainValid() throws {
    let source = try plan(["id": "answer", "type": "slot", "componentType": "text", "projected": false])
    let validated = try NativeLayoutSlots.validatePlan(source)
    #expect(validated.planData == source)
    #expect(validated.slots == [NativeLayoutSlots.Slot(id: "answer", componentType: .text, projected: false)])
    #expect(validated.slots.first?.purpose == nil)
  }

  // Given an authored purpose, when the slot is assembled, then the final layout contains only the public component.
  @Test func assemblyDoesNotLeakPurposeIntoLayout() throws {
    let normalized = try NativeLayoutSlots.normalizeNativePlan(plan(slot(purpose: "Explain the total, not the inputs.")))
    let component = try data(["id": "answer", "type": "text", "text": "Total: 42"])
    let assembled = try object(NativeLayoutSlots.assemble(plan: normalized, components: ["answer": component]))
    #expect(NSDictionary(dictionary: assembled).isEqual(to: ["version": 1, "root": try object(component), "floatingActions": []]))
    let root = try #require(assembled["root"] as? [String: Any])
    #expect(root["purpose"] == nil)
  }
}
