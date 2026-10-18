import Foundation
import SwiftUIIntelligence

struct AcceptedCalculationData: Sendable {
  let declarations: Data
  let outputIDs: [String: [String: String]]
  let recordInputRoles: [String: [String: String]]
  /// Capability → direction → parameter → authored scalar ID. Not a calculation binding.
  let scalarRoles: [String: [String: [String: String]]]

  init(declarations: Data, outputIDs: [String: [String: String]],
    scalarRoles: [String: [String: [String: String]]] = [:], recordInputRoles: [String: [String: String]] = [:]) {
    self.recordInputRoles = recordInputRoles
    self.declarations = declarations
    self.outputIDs = outputIDs
    self.scalarRoles = scalarRoles
  }
}

/// Uses signature metadata only. The caller validates the final document with the actual registry.
enum NativeCalculationData {
  private static var identifier: [String: Any] {
    ["type": "string", "minLength": 1, "maxLength": 64, "pattern": "^[A-Za-z0-9._-]+$"]
  }

  private static var collectionIdentifier: [String: Any] {
    ["type": "string", "minLength": 1, "maxLength": 64, "pattern": "^[A-Za-z0-9._-]+$",
     "description": "Unique identifier for this authored record collection. Must be unique across all collections."]
  }

  private static var rowIdentifier: [String: Any] {
    ["type": "string", "minLength": 1, "maxLength": 64, "pattern": "^[A-Za-z0-9._-]+$",
     "description": "Unique identifier for this row within this collection (e.g. 'row-1', 'row-2', etc.). Each row must have a distinct unique row ID; do not reuse referenced entity IDs or repeat row IDs across rows."]
  }

  static func dataSchema(from finiteSchema: Data, signatures: [CalculationRegistry.Signature]) throws -> Data {
    let schema = try object(finiteSchema)
    guard let properties = schema["properties"] as? [String: Any], let state = properties["state"] as? [String: Any] else {
      throw UIError("The finite schema requires a state array.")
    }
    var inputs: [String: Any] = [:]
    var outputs: [String: Any] = [:]
    for signature in signatures.sorted(by: { $0.id < $1.id }) {
      inputs[signature.id] = try closed(signature.recordInputs.mapValues(collectionSchema))
      outputs[signature.id] = closed(signature.recordOutputs.mapValues { _ in closed(["id": identifier]) })
    }
    return try encode(closed(["state": state, "recordInputs": closed(inputs), "recordOutputs": closed(outputs)]))
  }

  /// Optional role-based source format. Record slots keep the legacy source contract.
  static func roleDataSchema(from finiteSchema: Data, signatures: [CalculationRegistry.Signature],
    allowedKinds: Set<StateField.Kind> = Set(StateField.Kind.allCases)) throws -> Data {
    let legacy = try object(dataSchema(from: finiteSchema, signatures: signatures))
    let roles = try object(NativeScalarRoles.roleSchema(signatures: signatures, allowedKinds: allowedKinds))
    guard var properties = legacy["properties"] as? [String: Any],
      let roleProperties = roles["properties"] as? [String: Any],
      let declarations = roleProperties["declarations"] else {
      throw UIError("Role data requires scalar declaration properties.")
    }
    properties.removeValue(forKey: "state")
    properties["scalarRoles"] = declarations
    return try encode(closed(properties))
  }

  static func normalizeRoleData(_ data: Data, signatures: [CalculationRegistry.Signature]) throws -> AcceptedCalculationData {
    let source = try object(data)
    try exact(source, keys: ["scalarRoles", "recordInputs", "recordOutputs"])
    guard let declarations = source["scalarRoles"], let inputs = source["recordInputs"],
      let outputs = source["recordOutputs"] else {
      throw UIError("Role data requires scalarRoles, recordInputs, and recordOutputs.")
    }
    let roles = try NativeScalarRoles.normalizeRoles(encode(["declarations": declarations]), signatures: signatures)
    let state = try JSONSerialization.jsonObject(with: roles.stateArrayData)
    let accepted = try normalizeData(encode(["state": state, "recordInputs": inputs, "recordOutputs": outputs]),
      signatures: signatures)
    return AcceptedCalculationData(declarations: accepted.declarations, outputIDs: accepted.outputIDs, scalarRoles: roles.roles, recordInputRoles: accepted.recordInputRoles)
  }

  static func normalizeData(_ data: Data, signatures: [CalculationRegistry.Signature]) throws -> AcceptedCalculationData {
    let authored = try object(data)
    try exact(authored, keys: ["state", "recordInputs", "recordOutputs"])
    guard let state = authored["state"] as? [Any],
      let inputCapabilities = authored["recordInputs"] as? [String: Any],
      let outputCapabilities = authored["recordOutputs"] as? [String: Any] else {
      throw UIError("Data requires state, recordInputs, and recordOutputs with their declared types.")
    }
    for value in state {
      guard let declaration = value as? [String: Any], let rawKind = declaration["kind"] as? String,
        let kind = StateField.Kind(rawValue: rawKind) else { throw UIError("A state declaration requires a known kind.") }
      var keys: Set<String> = ["id", "kind", "value"]
      if kind == .number { keys.formUnion(["minimum", "maximum", "step"]) }
      if kind == .choice { keys.insert("options") }
      try exact(declaration, keys: keys)
    }
    let capabilities = Set(signatures.map(\.id))
    try exact(inputCapabilities, keys: capabilities)
    try exact(outputCapabilities, keys: capabilities)
    var records: [[String: Any]] = []
    var outputIDs: [String: [String: String]] = [:]
    var recordInputRoles: [String: [String: String]] = [:]
    var collectionIDs = Set<String>()
    for signature in signatures.sorted(by: { $0.id < $1.id }) {
      guard let inputs = inputCapabilities[signature.id] as? [String: Any],
        let outputs = outputCapabilities[signature.id] as? [String: Any] else {
        throw UIError("Each capability requires record input and output objects.")
      }
      try exact(inputs, keys: Set(signature.recordInputs.keys))
      try exact(outputs, keys: Set(signature.recordOutputs.keys))
      for parameter in signature.recordInputs.keys.sorted() {
        guard let collection = inputs[parameter] as? [String: Any] else { throw UIError("A record input requires a complete collection.") }
        let decoded = try JSONDecoder().decode(RecordCollection.self, from: encode(collection))
        guard decoded.schema.fields == signature.recordInputs[parameter]?.fields,
          collectionIDs.insert(decoded.id).inserted else {
          throw UIError("Record inputs require exact schemas and unique collection IDs.")
        }
        for row in decoded.rows {
          for value in row.values.values {
            if case .text(let text) = value, text.unicodeScalars.count > 1000 {
              throw UIError("Native record text exceeds the 1000-code-point limit.")
            }
          }
        }
        recordInputRoles[signature.id, default: [:]][parameter] = decoded.id
        records.append(collection)
      }
      var destinations: [String: String] = [:]
      for parameter in signature.recordOutputs.keys.sorted() {
        guard let destination = outputs[parameter] as? [String: Any] else { throw UIError("A record output requires an authored ID.") }
        try exact(destination, keys: ["id"])
        guard let id = destination["id"] as? String, validID(id), collectionIDs.insert(id).inserted else {
          throw UIError("Record output IDs must be valid and unique.")
        }
        destinations[parameter] = id
      }
      outputIDs[signature.id] = destinations
    }
    guard collectionIDs.count <= 16 else { throw UIError("Source and output collections must total at most 16.") }
    let declarations = try encode(["state": state, "records": records])
    _ = try document(declarations: declarations)
    return AcceptedCalculationData(declarations: declarations, outputIDs: outputIDs, recordInputRoles: recordInputRoles)
  }

  static func bindingSchema(data: AcceptedCalculationData, signatures: [CalculationRegistry.Signature]) throws -> Data {
    let declared = try document(declarations: data.declarations)
    var variants: [[String: Any]] = []
    for signature in signatures.sorted(by: { $0.id < $1.id }) {
      func scalars(_ kinds: [String: CalculationRegistry.ValueKind], direction: String) throws -> [String: Any] {
        var fields: [String: Any] = [:]
        for parameter in kinds.keys.sorted() {
          let ids = declared.state.filter { matches($0.kind, kinds[parameter]!) }.map(\.id).sorted()
          if data.scalarRoles.isEmpty {
            fields[parameter] = try candidates(ids)
          } else {
            guard let id = data.scalarRoles[signature.id]?[direction]?[parameter], ids.contains(id) else {
              throw UIError("A scalar binding requires its compatible authored role ID.")
            }
            fields[parameter] = try candidates([id])
          }
        }
        return closed(fields)
      }
      var inputs: [String: Any] = [:]
      for parameter in signature.recordInputs.keys.sorted() {
        let ids = declared.records.filter { $0.schema.fields == signature.recordInputs[parameter]?.fields }.map(\.id).sorted()
        if data.recordInputRoles.isEmpty {
          inputs[parameter] = try candidates(ids)
        } else {
          guard let id = data.recordInputRoles[signature.id]?[parameter], ids.contains(id) else {
            throw UIError("A record input requires its compatible authored role ID.")
          }
          inputs[parameter] = try candidates([id])
        }
      }
      var outputs: [String: Any] = [:]
      for parameter in signature.recordOutputs.keys.sorted() {
        guard let id = data.outputIDs[signature.id]?[parameter] else { throw UIError("A record output has no authored destination.") }
        outputs[parameter] = try candidates([id])
      }
      variants.append(try closed(["id": identifier, "capability": candidates([signature.id]),
        "inputs": scalars(signature.inputs, direction: "inputs"), "outputs": scalars(signature.outputs, direction: "outputs"),
        "recordInputs": closed(inputs), "recordOutputs": closed(outputs)]))
    }
    guard !variants.isEmpty else { throw UIError("Bindings require at least one selected capability.") }
    return try encode(closed(["calculations": ["type": "array", "minItems": signatures.count, "maxItems": signatures.count,
      "items": ["anyOf": variants]]]))
  }

  /// Checks bindings without executing capabilities or creating missing map entries.
  static func normalizeBindings(_ bindings: Data, data: AcceptedCalculationData,
    signatures: [CalculationRegistry.Signature]) throws -> Data {
    let authored = try object(bindings)
    try exact(authored, keys: ["calculations"])
    guard let calculations = authored["calculations"] as? [[String: Any]],
      !calculations.isEmpty, calculations.count == signatures.count,
      Set(calculations.compactMap { $0["capability"] as? String }) == Set(signatures.map(\.id)) else {
      throw UIError("Bindings require one calculation per authored capability slot.")
    }
    for calculation in calculations {
      try exact(calculation, keys: ["id", "capability", "inputs", "outputs", "recordInputs", "recordOutputs"])
    }
    var declarations = try object(data.declarations)
    declarations["calculations"] = calculations
    let result = try encode(declarations)
    let parsed = try document(declarations: result, capabilities: Set(signatures.map(\.id)))
    let fields = Dictionary(uniqueKeysWithValues: parsed.state.map { ($0.id, $0) })
    let collections = Dictionary(uniqueKeysWithValues: parsed.records.map { ($0.id, $0.schema) })
    for binding in parsed.calculations {
      guard let signature = signatures.first(where: { $0.id == binding.capability }),
        Set(binding.inputs.keys) == Set(signature.inputs.keys),
        Set(binding.outputs.keys) == Set(signature.outputs.keys),
        Set(binding.recordInputs.keys) == Set(signature.recordInputs.keys),
        Set(binding.recordOutputs.keys) == Set(signature.recordOutputs.keys) else {
        throw UIError("Calculation binding parameters must match the selected signature.")
      }
      for (direction, mapping, kinds) in [("inputs", binding.inputs, signature.inputs), ("outputs", binding.outputs, signature.outputs)] {
        for (parameter, id) in mapping {
          guard let field = fields[id], let kind = kinds[parameter], matches(field.kind, kind) else {
            throw UIError("A scalar binding requires a compatible authored state field.")
          }
          if !data.scalarRoles.isEmpty, data.scalarRoles[signature.id]?[direction]?[parameter] != id {
            throw UIError("A scalar binding must use its authored role ID.")
          }
        }
      }
      for (parameter, id) in binding.recordInputs {
        if !data.recordInputRoles.isEmpty, data.recordInputRoles[signature.id]?[parameter] != id {
          throw UIError("A record input must use its authored capability and parameter role ID.")
        }
        guard let schema = collections[id], schema.fields == signature.recordInputs[parameter]?.fields else {
          throw UIError("A record binding requires an authored source with the exact schema.")
        }
      }
      for (parameter, id) in binding.recordOutputs {
        guard data.outputIDs[signature.id]?[parameter] == id else {
          throw UIError("A record output must use its authored destination ID.")
        }
      }
    }
    return result
  }

  private static func document(declarations: Data, capabilities: Set<String> = []) throws -> UIDocument {
    var object = try object(declarations)
    object["version"] = 1
    object["root"] = ["id": "validation-root", "type": "text", "text": "Validation"]
    object["floatingActions"] = [Any]()
    return try UIDocument.decode(encode(object), registeredActions: [], registeredCalculations: capabilities)
  }

  private static func matches(_ field: StateField.Kind, _ kind: CalculationRegistry.ValueKind) -> Bool {
    switch (field, kind) {
    case (.number, .number), (.boolean, .boolean), (.text, .text), (.choice, .text), (.date, .text), (.date, .instant): true
    default: false
    }
  }

  private static func collectionSchema(_ schema: RecordSchema) throws -> [String: Any] {
    try schema.validate([])
    var values: [String: Any] = [:]
    var fields: [String: Any] = [:]
    for (name, kind) in schema.fields {
      fields[name] = ["type": "string", "enum": [kind.rawValue]]
      switch kind {
      case .text: values[name] = ["type": "string", "maxLength": 1000]
      case .number: values[name] = ["type": "number", "minimum": -1e9, "maximum": 1e9]
      case .boolean: values[name] = ["type": "boolean"]
      case .instant: throw UIError("Record fields do not support instant declarations.")
      }
    }
    return closed(["id": collectionIdentifier, "schema": closed(["fields": closed(fields)]),
      "rows": ["type": "array", "maxItems": 32, "items": closed(["id": rowIdentifier, "values": closed(values)])]])
  }

  private static func closed(_ fields: [String: Any]) -> [String: Any] {
    ["type": "object", "additionalProperties": false, "properties": fields, "required": fields.keys.sorted()]
  }

  private static func candidates(_ ids: [String]) throws -> [String: Any] {
    guard !ids.isEmpty else { throw UIError("A required binding has no compatible authored IDs.") }
    return ["type": "string", "enum": ids]
  }

  private static func validID(_ id: String) -> Bool {
    !id.isEmpty && id.utf8.count <= 64 && id.utf8.allSatisfy {
      (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || [45, 46, 95].contains($0)
    }
  }

  private static func exact(_ object: [String: Any], keys: Set<String>) throws {
    guard Set(object.keys) == keys, !object.values.contains(where: { $0 is NSNull }) else {
      throw UIError("The stage has missing, unknown, or null fields.")
    }
  }

  private static func object(_ data: Data) throws -> [String: Any] {
    guard data.count <= 65_536 else { throw UIError("JSON exceeds the 64 KiB limit.") }
    do {
      guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw UIError("The stage must be a JSON object.")
      }
      return object
    } catch let error as UIError { throw error }
    catch { throw UIError("Unable to decode stage JSON: \(error.localizedDescription)") }
  }

  private static func encode(_ object: [String: Any]) throws -> Data {
    try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
  }
}
