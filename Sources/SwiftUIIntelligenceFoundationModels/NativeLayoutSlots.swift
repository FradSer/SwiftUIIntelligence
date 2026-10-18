import CoreFoundation
import Foundation
import SwiftUIIntelligence

/// Keeps the model-authored layout separate from generated leaf components.
enum NativeLayoutSlots {
  struct Slot: Sendable, Equatable {
    let id: String
    let componentType: UINode.Kind
    let projected: Bool
    let purpose: String?

    init(id: String, componentType: UINode.Kind, projected: Bool, purpose: String? = nil) {
      self.id = id
      self.componentType = componentType
      self.projected = projected
      self.purpose = purpose
    }
  }

  struct ValidatedPlan: Sendable {
    let slots: [Slot]
    let planData: Data
  }

  private static let containers: Set<UINode.Kind> = [.vstack, .hstack, .grid, .section, .form]
  private static let supported: Set<UINode.Kind> = [.text, .control, .metric, .list, .table, .chart, .timeline]
  private static let projections: Set<UINode.Kind> = [.list, .table, .chart, .timeline]
  private static var identifierSchema: [String: Any] { [
    "type": "string", "minLength": 1, "maxLength": 64, "pattern": "^[A-Za-z0-9._-]+$",
  ] }

  /// Recursive references keep the schema compact. Runtime validation limits depth, node count, and slot count.
  static func planSchema(componentTypes: [UINode.Kind], registeredActions: Set<String>) throws -> Data {
    guard !componentTypes.isEmpty, Set(componentTypes).isSubset(of: supported) else {
      throw UIError("The native layout supports only text, control, metric, list, table, chart, and timeline slots.")
    }
    let kinds = Set(componentTypes).sorted { $0.rawValue < $1.rawValue }
    func object(_ fields: [String: Any], required: [String]? = nil) -> [String: Any] {
      ["type": "object", "additionalProperties": false, "properties": fields,
        "required": required ?? fields.keys.sorted()]
    }
    func slot(_ kind: UINode.Kind) -> [String: Any] {
      object(["id": identifierSchema, "type": ["type": "string", "enum": ["slot"]],
        "componentType": ["type": "string", "enum": [kind.rawValue]],
        "projected": ["type": "boolean", "enum": projections.contains(kind) ? [false, true] : [false]]])
    }
    var definitions: [String: Any] = ["Slot": ["anyOf": kinds.map(slot)]]
    var branches: [[String: Any]] = [["$ref": "#/$defs/Slot"]]
    for kind in containers.sorted(by: { $0.rawValue < $1.rawValue }) {
      var fields: [String: Any] = ["id": identifierSchema, "type": ["type": "string", "enum": [kind.rawValue]],
        "children": ["type": "array", "maxItems": 32, "items": ["$ref": "#/$defs/Node"]],
        "spacing": ["type": "number", "minimum": 0, "maximum": 48]]
      var required = ["id", "type", "children"]
      if kind == .grid {
        fields["columnCount"] = ["type": "integer", "minimum": 1, "maximum": 6]
        required.append("columnCount")
      }
      if kind == .section || kind == .form {
        fields["title"] = ["type": "string", "minLength": 1, "maxLength": 160]
        fields["icon"] = identifierSchema
        required.append("title")
      }
      branches.append(object(fields, required: required.sorted()))
    }
    definitions["Node"] = ["anyOf": branches]
    var result = object(["version": ["type": "integer", "enum": [1]], "root": ["$ref": "#/$defs/Node"],
      "floatingActions": ["type": "array", "maxItems": 0, "items": object([:])]])
    result["$defs"] = definitions
    return try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
  }

  /// Uses explicit mode names for native generation without changing the internal plan schema.
  static func nativePlanSchema(componentTypes: [UINode.Kind], registeredActions: Set<String>) throws -> Data {
    var schema = try decodeObject(planSchema(componentTypes: componentTypes, registeredActions: registeredActions))
    guard var definitions = schema["$defs"] as? [String: [String: Any]],
      var slotDefinition = definitions["Slot"], var branches = slotDefinition["anyOf"] as? [[String: Any]] else {
      throw UIError("The layout schema requires slot definitions.")
    }
    for index in branches.indices {
      guard var fields = branches[index]["properties"] as? [String: [String: Any]],
        let projected = fields.removeValue(forKey: "projected"), let values = projected["enum"] as? [Bool],
        let required = branches[index]["required"] as? [String] else {
        throw UIError("The layout schema requires slot projection fields.")
      }
      fields["mode"] = ["type": "string", "enum": values.map { $0 ? "records" : "static" }]
      fields["purpose"] = ["type": "string", "minLength": 1, "maxLength": 500]
      branches[index]["properties"] = fields
      branches[index]["required"] = (required.map { $0 == "projected" ? "mode" : $0 } + ["purpose"]).sorted()
    }
    slotDefinition["anyOf"] = branches
    definitions["Slot"] = slotDefinition
    schema["$defs"] = definitions
    return try JSONSerialization.data(withJSONObject: schema, options: [.sortedKeys])
  }

  /// Converts authored modes to internal projection flags, then validates without adding missing fields.
  static func normalizeNativePlan(_ data: Data) throws -> Data {
    var plan = try decodeObject(data)
    func normalize(_ value: Any?, depth: Int) throws -> [String: Any] {
      guard depth <= 12, var node = value as? [String: Any] else {
        throw UIError("Layout nodes require objects and at most twelve levels.")
      }
      if node["type"] as? String == "slot" {
        guard node["projected"] == nil, let mode = node["mode"] as? String,
          mode == "static" || mode == "records" else {
          throw UIError("A native slot requires mode static or records and cannot include projected.")
        }
        guard let purpose = node["purpose"] as? String, validPurpose(purpose) else {
          throw UIError("A native slot requires purpose text of one to 500 characters.")
        }
        node.removeValue(forKey: "mode")
        node["projected"] = mode == "records"
      } else if let children = node["children"] as? [Any] {
        node["children"] = try children.map { try normalize($0, depth: depth + 1) }
      }
      return node
    }
    plan["root"] = try normalize(plan["root"], depth: 1)
    if plan["floatingActions"] == nil {
      plan["floatingActions"] = [[String: Any]]()
    }
    let normalized = try JSONSerialization.data(withJSONObject: plan, options: [.sortedKeys])
    _ = try validatePlan(normalized)
    return normalized
  }

  static func validatePlan(_ data: Data, requirements: DocumentRequirements = .init()) throws -> ValidatedPlan {
    let plan = try decodeObject(data)
    guard Set(plan.keys) == ["version", "root", "floatingActions"], number(plan["version"]) == 1,
      let floating = plan["floatingActions"] as? [[String: Any]], floating.isEmpty else {
      throw UIError("The native layout plan requires version 1, root, and empty floatingActions.")
    }
    var ids = Set<String>()
    var slots = [Slot]()
    var count = 0
    var kinds = Set<UINode.Kind>()
    func visit(_ value: Any?, depth: Int) throws {
      count += 1
      guard count <= 128, depth <= 12, let node = value as? [String: Any],
        let id = node["id"] as? String, validID(id), ids.insert(id).inserted,
        let type = node["type"] as? String else {
        throw UIError("Layout nodes require unique valid IDs, at most 128 nodes, and at most twelve levels.")
      }
      if type == "slot" {
        let required: Set<String> = ["id", "type", "componentType", "projected"]
        guard required.isSubset(of: Set(node.keys)), Set(node.keys).isSubset(of: required.union(["purpose"])),
          let rawKind = node["componentType"] as? String, let kind = UINode.Kind(rawValue: rawKind),
          supported.contains(kind), let projected = node["projected"] as? NSNumber,
          CFGetTypeID(projected) == CFBooleanGetTypeID(),
          !projected.boolValue || projections.contains(kind) else {
          throw UIError("Slot '\(id)' requires a supported leaf kind. Text, control, and metric slots require projected=false. Only list, table, chart, and timeline support projected=true.")
        }
        if let value = node["purpose"] {
          guard let purpose = value as? String, validPurpose(purpose) else {
            throw UIError("Slot purpose must be text of one to 500 characters when present.")
          }
        }
        kinds.insert(kind)
        slots.append(Slot(id: id, componentType: kind, projected: projected.boolValue, purpose: node["purpose"] as? String))
        guard slots.count <= 32 else { throw UIError("A layout plan accepts at most 32 slots.") }
        return
      }
      guard let kind = UINode.Kind(rawValue: type), containers.contains(kind),
        let children = node["children"] as? [[String: Any]], children.count <= 32 else {
        throw UIError("A layout container requires a supported kind and at most 32 children.")
      }
      kinds.insert(kind)
      var allowed: Set<String> = ["id", "type", "children", "spacing"]
      if kind == .grid {
        allowed.insert("columnCount")
        guard let columns = number(node["columnCount"]), (1...6).contains(columns), columns.rounded() == columns else {
          throw UIError("A grid requires one to six columns.")
        }
      }
      if kind == .section || kind == .form {
        allowed.formUnion(["title", "icon"])
        guard let title = node["title"] as? String, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          title.count <= 160 else { throw UIError("A section or form requires a title of one to 160 characters.") }
        if let icon = node["icon"] {
          guard let icon = icon as? String, validID(icon) else { throw UIError("Invalid layout icon key.") }
        }
      }
      guard Set(node.keys).isSubset(of: allowed) else { throw UIError("Unknown layout container field.") }
      if let spacing = node["spacing"] {
        guard let spacing = number(spacing), (0...48).contains(spacing) else {
          throw UIError("Layout spacing must be between zero and 48.")
        }
      }
      for child in children { try visit(child, depth: depth + 1) }
    }
    try visit(plan["root"], depth: 1)
    let projectedKinds = Set(slots.filter(\.projected).map(\.componentType))
    guard requirements.projectedComponents.isSubset(of: projectedKinds) else {
      throw UIError("Layout plan requires record-backed components: \(requirements.projectedComponents.map(\.rawValue).sorted()). Choose records mode for these requested views.")
    }
    guard requirements.components.union(requirements.projectedComponents).isSubset(of: kinds),
      slots.filter({ $0.componentType == .control }).count >= requirements.controls.count else {
      throw UIError("Layout plan omits host-required components or input controls.")
    }
    return ValidatedPlan(slots: slots, planData: data)
  }

  /// Replaces slots only. The caller must validate the final document with its accepted declarations and host registrations.
  static func assemble(plan: Data, components: [String: Data]) throws -> Data {
    let validated = try validatePlan(plan)
    guard Set(components.keys) == Set(validated.slots.map(\.id)) else {
      throw UIError("Components must match the layout slot IDs exactly.")
    }
    var replacements = [String: [String: Any]]()
    for slot in validated.slots {
      guard let data = components[slot.id] else { throw UIError("Missing layout component.") }
      let component = try decodeObject(data)
      guard component["id"] as? String == slot.id, component["type"] as? String == slot.componentType.rawValue,
        component["children"] == nil else { throw UIError("A component must match its slot ID and leaf kind.") }
      if slot.projected {
        guard component["recordSource"] is String, component["recordFields"] is [String] else {
          throw UIError("A projected slot requires explicit collection and field bindings.")
        }
      } else {
        guard component["recordSource"] == nil, component["recordFields"] == nil, component["editableFields"] == nil else {
          throw UIError("A static slot cannot accept record projection fields.")
        }
      }
      do { _ = try JSONDecoder().decode(UINode.self, from: data) }
      catch { throw UIError("Invalid component for layout slot '\(slot.id)'.") }
      replacements[slot.id] = component
    }
    func replace(_ node: [String: Any]) throws -> [String: Any] {
      if node["type"] as? String == "slot" {
        guard let id = node["id"] as? String, let component = replacements[id] else {
          throw UIError("Missing layout component.")
        }
        return component
      }
      var result = node
      if let children = node["children"] as? [[String: Any]] { result["children"] = try children.map(replace) }
      return result
    }
    var result = try decodeObject(plan)
    guard let root = result["root"] as? [String: Any], let floating = result["floatingActions"] as? [[String: Any]] else {
      throw UIError("Invalid layout plan.")
    }
    result["root"] = try replace(root)
    result["floatingActions"] = try floating.map(replace)
    return try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
  }

  private static func decodeObject(_ data: Data) throws -> [String: Any] {
    do {
      guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw UIError("The layout requires a JSON object.")
      }
      return object
    } catch { throw UIError("The layout requires a valid JSON object.") }
  }

  private static func number(_ value: Any?) -> Double? {
    guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite else { return nil }
    return value.doubleValue
  }

  private static func validPurpose(_ value: String) -> Bool {
    !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && value.unicodeScalars.count <= 500
  }

  private static func validID(_ value: String) -> Bool {
    !value.isEmpty && value.utf8.count <= 64 && value.utf8.allSatisfy {
      (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || [45, 46, 95].contains($0)
    }
  }
}
