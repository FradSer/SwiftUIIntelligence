import Foundation
import SwiftUIIntelligence

struct AcceptedScalarRoles: Sendable {
  /// The authored declarations as a JSON array, without decoder defaults or synthesized fields.
  let stateArrayData: Data
  /// Capability → direction (inputs/outputs) → parameter → authored state ID.
  /// This is stage metadata, not a public calculation binding.
  let roles: [String: [String: [String: String]]]
}

/// Collects complete scalar declarations by selected signature role. It never infers bindings or values.
enum NativeScalarRoles {
  static func roleSchema(signatures: [CalculationRegistry.Signature],
    allowedKinds: Set<StateField.Kind> = Set(StateField.Kind.allCases)) throws -> Data {
    try validateSignatures(signatures)
    let finite = try object(DocumentGenerationContract.schemaJSON())
    guard let properties = finite["properties"] as? [String: Any],
      let state = properties["state"] as? [String: Any],
      let items = state["items"] as? [String: Any],
      let variants = items["anyOf"] as? [[String: Any]] else {
      throw UIError("The finite schema requires canonical scalar declarations.")
    }
    let reference = closed(["reference": identifier])
    func parameters(_ kinds: [String: CalculationRegistry.ValueKind],
      constraints: [String: InputNumberConstraint] = [:]) throws -> [String: Any] {
      var slots: [String: Any] = [:]
      for parameter in kinds.keys.sorted() {
        guard let kind = kinds[parameter] else { continue }
        var compatible = variants.filter { variant in
          guard let properties = variant["properties"] as? [String: [String: Any]],
            let name = (properties["kind"]?["enum"] as? [String])?.first,
            let fieldKind = StateField.Kind(rawValue: name) else { return false }
          return allowedKinds.contains(fieldKind) && matches(fieldKind, kind)
        }
        guard !compatible.isEmpty else { throw UIError("A scalar role has no allowed declaration kind.") }
        compatible = compatible.map { variant in
          var variant = variant
          guard var properties = variant["properties"] as? [String: [String: Any]] else { return variant }
          if var idProp = properties["id"] {
            idProp["description"] = "Unique identifier for this state field (e.g. 'input_value'). Use letters, digits, underscores, or hyphens only; never embed colons, dates, or timestamps."
            properties["id"] = idProp
          }
          if let constraint = constraints[parameter] {
            for name in ["value", "minimum", "maximum"] {
              properties[name] = ["type": constraint.integer ? "integer" : "number",
                "minimum": constraint.minimum, "maximum": constraint.maximum]
            }
            if let step = constraint.step {
              properties["step"] = ["type": "number", "minimum": step, "maximum": step, "enum": [step]]
            } else if constraint.integer {
              properties["step"] = ["type": "integer", "minimum": 1, "maximum": 1e9]
            }
          }
          variant["properties"] = properties
          return variant
        }
        slots[parameter] = ["anyOf": compatible + [reference]]
      }
      return closed(slots)
    }
    var capabilities: [String: Any] = [:]
    for signature in signatures.sorted(by: { $0.id < $1.id }) {
      capabilities[signature.id] = try closed([
        "inputs": parameters(signature.inputs, constraints: signature.inputNumberConstraints),
        "outputs": parameters(signature.outputs),
      ])
    }
    return try encode(closed(["declarations": closed(capabilities)]))
  }

  static func normalizeRoles(_ data: Data, signatures: [CalculationRegistry.Signature]) throws -> AcceptedScalarRoles {
    try validateSignatures(signatures)
    let root = try object(data)
    try exact(root, keys: ["declarations"])
    guard let capabilities = root["declarations"] as? [String: Any] else {
      throw UIError("Scalar roles require a declarations object.")
    }
    try exact(capabilities, keys: Set(signatures.map(\.id)))
    var declarations: [[String: Any]] = []
    var fields: [String: StateField] = [:]
    var roles: [String: [String: [String: String]]] = [:]
    // Collect all full declarations first, so explicit references can point forward.
    for signature in signatures.sorted(by: { $0.id < $1.id }) {
      guard let directions = capabilities[signature.id] as? [String: Any] else {
        throw UIError("Each selected capability requires scalar role objects.")
      }
      try exact(directions, keys: ["inputs", "outputs"])
      var roleDirections: [String: [String: String]] = [:]
      for (direction, kinds) in [("inputs", signature.inputs), ("outputs", signature.outputs)] {
        guard let parameters = directions[direction] as? [String: Any] else {
          throw UIError("Each scalar direction requires an object.")
        }
        try exact(parameters, keys: Set(kinds.keys))
        var roleParameters: [String: String] = [:]
        for parameter in kinds.keys.sorted() {
          guard let declaration = parameters[parameter] as? [String: Any] else {
            throw UIError("Each scalar role requires a full declaration or an explicit reference.")
          }
          if declaration["reference"] != nil {
            try exact(declaration, keys: ["reference"])
            guard let id = declaration["reference"] as? String else { throw UIError("A scalar reference requires an ID.") }
            roleParameters[parameter] = id
          } else {
            guard let name = declaration["kind"] as? String, let kind = StateField.Kind(rawValue: name) else {
              throw UIError("A scalar declaration requires a known state kind.")
            }
            var keys: Set<String> = ["id", "kind", "value"]
            if kind == .number { keys.formUnion(["minimum", "maximum", "step"]) }
            if kind == .choice { keys.insert("options") }
            try exact(declaration, keys: keys)
            if let text = declaration["value"] as? String, text.unicodeScalars.count > 4000 {
              throw UIError("Scalar text exceeds the 4000-code-point limit.")
            }
            if let options = declaration["options"] as? [String], options.contains(where: { $0.unicodeScalars.count > 80 }) {
              throw UIError("Choice text exceeds the 80-code-point limit.")
            }
            let field = try JSONDecoder().decode(StateField.self, from: encode(declaration))
            guard fields[field.id] == nil else { throw UIError("Full scalar declarations must have unique IDs, even when values match.") }
            fields[field.id] = field
            declarations.append(declaration)
            roleParameters[parameter] = field.id
          }
        }
        roleDirections[direction] = roleParameters
      }
      roles[signature.id] = roleDirections
    }
    guard declarations.count <= 32 else { throw UIError("Scalar roles require at most 32 unique declarations.") }
    for signature in signatures {
      for (direction, kinds) in [("inputs", signature.inputs), ("outputs", signature.outputs)] {
        for (parameter, kind) in kinds {
          guard let id = roles[signature.id]?[direction]?[parameter], let field = fields[id], matches(field.kind, kind) else {
            throw UIError("A scalar role must reference a full declaration with a compatible kind in this response.")
          }
          if direction == "inputs", let constraint = signature.inputNumberConstraints[parameter] {
            try constraint.validate(field: field)
          }
        }
      }
    }
    // Validate canonical state constraints, but retain the original objects rather than re-encoding decoded fields.
    let validation: [String: Any] = ["version": 1, "state": declarations,
      "root": ["id": "validation-root", "type": "text", "text": "Validation"], "floatingActions": [Any]()]
    _ = try UIDocument.decode(encode(validation), registeredActions: [])
    return AcceptedScalarRoles(stateArrayData: try encode(declarations), roles: roles)
  }

  private static var identifier: [String: Any] {
    ["type": "string", "minLength": 1, "maxLength": 64, "pattern": "^[A-Za-z0-9._-]+$"]
  }

  private static func matches(_ field: StateField.Kind, _ kind: CalculationRegistry.ValueKind) -> Bool {
    switch (field, kind) {
    case (.number, .number), (.boolean, .boolean), (.text, .text), (.choice, .text), (.date, .text), (.date, .instant): true
    default: false
    }
  }

  private static func validateSignatures(_ signatures: [CalculationRegistry.Signature]) throws {
    guard Set(signatures.map(\.id)).count == signatures.count else { throw UIError("Selected scalar signatures must be unique.") }
    for signature in signatures {
      for (parameter, constraint) in signature.inputNumberConstraints {
        guard signature.inputs[parameter] == .number else {
          throw UIError("Scalar numeric constraints require numeric input roles.")
        }
        try constraint.validate()
      }
    }
  }

  private static func closed(_ properties: [String: Any]) -> [String: Any] {
    ["type": "object", "additionalProperties": false, "properties": properties, "required": properties.keys.sorted()]
  }

  private static func exact(_ object: [String: Any], keys: Set<String>) throws {
    guard Set(object.keys) == keys, !object.values.contains(where: { $0 is NSNull }) else {
      throw UIError("Scalar roles have missing, unknown, or null fields.")
    }
  }

  private static func object(_ data: Data) throws -> [String: Any] {
    guard data.count <= 65_536 else { throw UIError("JSON exceeds the 64 KiB limit.") }
    do {
      guard let result = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw UIError("Scalar roles require a JSON object.")
      }
      return result
    } catch let error as UIError { throw error }
    catch { throw UIError("Unable to decode scalar roles: \(error.localizedDescription)") }
  }

  private static func encode(_ value: Any) throws -> Data {
    try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
  }
}
