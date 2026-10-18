import Foundation
import SwiftUIIntelligence
@testable import SwiftUIIntelligenceFoundationModels
import Testing

@Suite struct NativeLayoutSlotsTests {
  private func data(_ value: Any) throws -> Data {
    try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
  }

  private func object(_ value: Data) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: value) as? [String: Any])
  }

  private func slot(_ id: String = "answer", _ kind: String = "text", projected: Bool = false) -> [String: Any] {
    ["id": id, "type": "slot", "componentType": kind, "projected": projected]
  }

  private func plan(_ root: [String: Any], floating: [[String: Any]] = []) throws -> Data {
    try data(["version": 1, "root": root, "floatingActions": floating])
  }

  // Given selected leaf kinds, when a schema is built, then compact recursive references preserve the required container fields.
  @Test func schemaScopesKindsAndBoundsReferences() throws {
    let schema = try object(NativeLayoutSlots.planSchema(componentTypes: [.text, .list], registeredActions: []))
    let definitions = try #require(schema["$defs"] as? [String: [String: Any]])
    let slots = try #require(definitions["Slot"]?["anyOf"] as? [[String: Any]])
    let kinds = slots.compactMap { ($0["properties"] as? [String: [String: Any]])?["componentType"]?["enum"] as? [String] }.flatMap { $0 }
    #expect(Set(kinds) == ["text", "list"])
    #expect(Set(definitions.keys) == ["Node", "Slot"])
    #expect((schema["properties"] as? [String: [String: Any]])?["root"]?["$ref"] as? String == "#/$defs/Node")
    let branches = try #require(definitions["Node"]?["anyOf"] as? [[String: Any]])
    for container in branches.dropFirst() {
      let properties = try #require(container["properties"] as? [String: [String: Any]])
      #expect(properties["children"]?["maxItems"] as? Int == 32)
      #expect((properties["children"]?["items"] as? [String: Any])?["$ref"] as? String == "#/$defs/Node")
      let kind = try #require(properties["type"]?["enum"] as? [String]).first
      let required = try #require(container["required"] as? [String])
      if kind == "section" || kind == "form" { #expect(required.contains("title")) }
      if kind == "grid" { #expect(required.contains("columnCount")) }
    }
    let full = try NativeLayoutSlots.planSchema(componentTypes: [.text, .control, .list, .table, .chart, .timeline], registeredActions: [])
    #expect(full.count < 15_000)
    let fullObject = try object(full)
    let fullDefinitions = try #require(fullObject["$defs"] as? [String: Any])
    func checkReferences(_ value: Any) {
      if let fields = value as? [String: Any] {
        #expect(fields["not"] == nil)
        if let reference = fields["$ref"] as? String {
          #expect(reference.hasPrefix("#/$defs/"))
          #expect(fullDefinitions[String(reference.dropFirst("#/$defs/".count))] != nil)
        }
        for child in fields.values { checkReferences(child) }
      } else if let array = value as? [Any] {
        for child in array { checkReferences(child) }
      }
    }
    checkReferences(fullObject)
    #expect(throws: UIError.self) { try NativeLayoutSlots.planSchema(componentTypes: [], registeredActions: []) }
    let fields = try #require(schema["properties"] as? [String: [String: Any]])
    #expect(fields["floatingActions"]?["maxItems"] as? Int == 0)
    #expect(schema["additionalProperties"] as? Bool == false)
    for kind: UINode.Kind in [.button, .navigationLink, .vstack] {
      #expect(throws: UIError.self) {
        try NativeLayoutSlots.planSchema(componentTypes: [kind], registeredActions: ["save"])
      }
      #expect(throws: UIError.self) { try NativeLayoutSlots.validatePlan(plan(slot("unsupported", kind.rawValue))) }
    }
  }

  @Test func planChecksHostRequiredComponentsAndControlCountBeforeGeneration() throws {
    let requirements = DocumentRequirements(components: [.table, .timeline], controls: [.stepper, .datePicker])
    let incomplete = try plan(slot("text", "text"))
    #expect(throws: UIError.self) { try NativeLayoutSlots.validatePlan(incomplete, requirements: requirements) }
    let complete = try plan(["id": "root", "type": "vstack", "children": [
      slot("count", "control"), slot("when", "control"), slot("shopping", "table", projected: true), slot("steps", "timeline", projected: true)
    ]])
    #expect(try NativeLayoutSlots.validatePlan(complete, requirements: requirements).slots.count == 4)
  }

  @Test func projectedRequirementsRejectStaticPlanWithoutChangingIt() throws {
    let requirements = DocumentRequirements(projectedComponents: [.table, .timeline])
    let staticPlan = try plan(["id": "root", "type": "vstack", "children": [slot("table", "table"), slot("time", "timeline")]])
    #expect(throws: UIError.self) { try NativeLayoutSlots.validatePlan(staticPlan, requirements: requirements) }
    let dynamicPlan = try plan(["id": "root", "type": "vstack", "children": [slot("table", "table", projected: true), slot("time", "timeline", projected: true)]])
    #expect(try NativeLayoutSlots.validatePlan(dynamicPlan, requirements: requirements).planData == dynamicPlan)
  }

  // Given an authored tree, when slots are filled, then containers, values, and child order remain unchanged.
  @Test func preservesAuthoredTreeAndCollectsSlotsInOrder() throws {
    let root: [String: Any] = ["id": "root", "type": "form", "title": "Authored form", "icon": "edit", "spacing": 0,
      "children": [["id": "group", "type": "section", "title": "Authored section", "children": [
        ["id": "row", "type": "hstack", "spacing": 7.5, "children": [slot("second"), slot("first")]],
        ["id": "grid", "type": "grid", "columnCount": 6, "spacing": 48, "children": [slot("records", "list", projected: true)]]
      ]]]]
    let source = try plan(root)
    let validated = try NativeLayoutSlots.validatePlan(source)
    #expect(validated.planData == source)
    #expect(validated.slots.map(\.id) == ["second", "first", "records"])
    #expect(validated.slots.map(\.componentType) == [.text, .text, .list])
    #expect(validated.slots.map(\.projected) == [false, false, true])
    let components = try ["second": data(["id": "second", "type": "text", "text": "B"]),
      "first": data(["id": "first", "type": "text", "text": "A"]),
      "records": data(["id": "records", "type": "list", "items": [], "recordSource": "results", "recordFields": ["name"]])]
    let output = try object(NativeLayoutSlots.assemble(plan: source, components: components))
    #expect(Set(output.keys) == ["version", "root", "floatingActions"])
    var expectedRoot = root
    var groups = try #require(root["children"] as? [[String: Any]])
    var children = try #require(groups[0]["children"] as? [[String: Any]])
    children[0]["children"] = try [object(components["second"]!), object(components["first"]!)]
    children[1]["children"] = try [object(components["records"]!)]
    groups[0]["children"] = children
    expectedRoot["children"] = groups
    #expect(NSDictionary(dictionary: output).isEqual(to: ["version": 1, "root": expectedRoot,
      "floatingActions": []]))
    #expect(try NativeLayoutSlots.validatePlan(source).planData == source)
  }

  @Test func normalizeNativePlanDefaultsMissingFloatingActionsToEmpty() throws {
    let raw = try data(["version": 1, "root": ["id": "slot1", "type": "slot", "componentType": "text", "mode": "static", "purpose": "text"]])
    let normalized = try NativeLayoutSlots.normalizeNativePlan(raw)
    let validated = try NativeLayoutSlots.validatePlan(normalized)
    #expect(validated.slots.count == 1)
  }

  @Test func assemblyEnforcesAuthoredProjectionMode() throws {
    let staticNode = try data(["id": "answer", "type": "list", "items": ["Static"]])
    let projectedNode = try data(["id": "answer", "type": "list", "items": ["Pending"], "recordSource": "results", "recordFields": ["name"]])
    let projectedPlan = try plan(slot("answer", "list", projected: true))
    let staticPlan = try plan(slot("answer", "list", projected: false))
    #expect(throws: UIError.self) { try NativeLayoutSlots.assemble(plan: projectedPlan, components: ["answer": staticNode]) }
    #expect(throws: UIError.self) { try NativeLayoutSlots.assemble(plan: staticPlan, components: ["answer": projectedNode]) }
    _ = try NativeLayoutSlots.assemble(plan: projectedPlan, components: ["answer": projectedNode])
    _ = try NativeLayoutSlots.assemble(plan: staticPlan, components: ["answer": staticNode])
  }

  // Given incomplete or mismatched components, when assembled, then replacement fails instead of repairing the output.
  @Test func rejectsMissingExtraAndInvalidComponents() throws {
    let source = try plan(slot())
    let good = try data(["id": "answer", "type": "text", "text": "Answer"])
    for components: [String: Data] in [[:], ["answer": good, "extra": good],
      ["answer": try data(["id": "other", "type": "text", "text": "Answer"])],
      ["answer": try data(["id": "answer", "type": "button", "title": "Wrong", "action": "save"])],
      ["answer": Data("null".utf8)],
      ["answer": try data(["id": "answer", "type": "text", "text": "Answer", "children": []])],
      ["answer": try data(["id": "answer", "type": "text", "text": NSNull()])]] {
      #expect(throws: UIError.self) { try NativeLayoutSlots.assemble(plan: source, components: components) }
    }
    #expect(try object(NativeLayoutSlots.assemble(plan: source, components: ["answer": good]))["root"] != nil)
  }

  // Given malformed plans, when validated, then strict keys, types, and per-kind properties prevent silent defaults.
  @Test func rejectsInvalidPlanGrammar() throws {
    let invalidRoots: [[String: Any]] = [
      ["id": "root", "type": "text", "text": "Not a slot"],
      ["id": "root", "type": "vstack"],
      ["id": "root", "type": "vstack", "children": [], "title": "Wrong kind"],
      ["id": "root", "type": "section", "children": []],
      ["id": "root", "type": "form", "title": NSNull(), "children": []],
      ["id": "root", "type": "grid", "children": []],
      ["id": "root", "type": "grid", "columnCount": true, "children": []],
      ["id": "root", "type": "vstack", "spacing": NSNull(), "children": []],
      ["id": "root", "type": "vstack", "spacing": true, "children": []],
      ["id": "root", "type": "slot", "componentType": "vstack", "projected": false],
      ["id": "root", "type": "slot", "componentType": "text", "projected": true],
      ["id": "root", "type": "slot", "componentType": "text", "projected": 0],
      ["id": "root", "type": "slot", "componentType": "text"],
      ["id": "root", "type": "slot", "componentType": "text", "projected": false, "title": "Extra"],
      ["id": "bad id", "type": "vstack", "children": []],
    ]
    for root in invalidRoots {
      #expect(throws: UIError.self) { try NativeLayoutSlots.validatePlan(plan(root)) }
    }
    for raw in ["null", "[]", "{\"version\":true,\"root\":{},\"floatingActions\":[]}"] {
      #expect(throws: UIError.self) { try NativeLayoutSlots.validatePlan(Data(raw.utf8)) }
    }
    var extra = try object(plan(slot()))
    extra["state"] = []
    #expect(throws: UIError.self) { try NativeLayoutSlots.validatePlan(data(extra)) }
    #expect(throws: UIError.self) { try NativeLayoutSlots.validatePlan(plan(slot(), floating: [slot("floating")])) }
    #expect(throws: UIError.self) { try NativeLayoutSlots.validatePlan(plan(slot(), floating: [slot("answer", "button")])) }
  }

  // Given resource boundaries, when validated, then valid limits pass and excessive or duplicate nodes fail.
  @Test func enforcesResourceBoundsAndUniqueIDs() throws {
    for spacing in [0, 48] {
      _ = try NativeLayoutSlots.validatePlan(plan(["id": "root", "type": "vstack", "spacing": spacing, "children": []]))
    }
    for root: [String: Any] in [
      ["id": "root", "type": "vstack", "spacing": -1, "children": []],
      ["id": "root", "type": "vstack", "spacing": 49, "children": []],
      ["id": "root", "type": "grid", "columnCount": 7, "children": []],
      ["id": "root", "type": "section", "title": String(repeating: "a", count: 161), "children": []],
      ["id": "root", "type": "vstack", "children": [slot("root")]],
      ["id": "root", "type": "vstack", "children": [slot(), slot()]],
      ["id": "root", "type": "vstack", "children": (0..<33).map { slot("s\($0)") }],
    ] {
      #expect(throws: UIError.self) { try NativeLayoutSlots.validatePlan(plan(root)) }
    }
    var nested = slot()
    for level in 1...11 { nested = ["id": "n\(level)", "type": "vstack", "children": [nested]] }
    _ = try NativeLayoutSlots.validatePlan(plan(nested))
    nested = ["id": "tooDeep", "type": "vstack", "children": [nested]]
    #expect(throws: UIError.self) { try NativeLayoutSlots.validatePlan(plan(nested)) }
    let slots = (0..<32).map { slot("s\($0)") }
    _ = try NativeLayoutSlots.validatePlan(plan(["id": "root", "type": "vstack", "children": slots]))
    #expect(throws: UIError.self) {
      try NativeLayoutSlots.validatePlan(plan(["id": "root", "type": "vstack", "children": [
        ["id": "a", "type": "vstack", "children": slots], ["id": "b", "type": "vstack", "children": [slot("extra")]]]]))
    }
    let groups: [[String: Any]] = (0..<4).map { group in
      ["id": "g\(group)", "type": "vstack", "children": (0..<31).map { child in
        ["id": "c\(group)-\(child)", "type": "vstack", "children": []] as [String: Any]
      }]
    }
    #expect(throws: UIError.self) { try NativeLayoutSlots.validatePlan(plan(["id": "root", "type": "vstack", "children": groups])) }
  }
}
