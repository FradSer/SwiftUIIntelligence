import Foundation

/// Names map capability parameters to declared state field IDs, never property paths.
public struct CalculationBinding: Codable, Sendable {
  public let id: String
  public let capability: String
  public let inputs: [String: String]
  public let outputs: [String: String]
  public let recordInputs: [String: String]
  public let recordOutputs: [String: String]

  private enum CodingKeys: String, CodingKey { case id, capability, inputs, outputs, recordInputs, recordOutputs }

  public init(from decoder: any Decoder) throws {
    try checkKeys(decoder, allowed: ["id", "capability", "inputs", "outputs", "recordInputs", "recordOutputs"])
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    capability = try container.decode(String.self, forKey: .capability)
    inputs = try container.decode([String: String].self, forKey: .inputs)
    outputs = try container.decode([String: String].self, forKey: .outputs)
    recordInputs = container.contains(.recordInputs) ? try container.decode([String: String].self, forKey: .recordInputs) : [:]
    recordOutputs = container.contains(.recordOutputs) ? try container.decode([String: String].self, forKey: .recordOutputs) : [:]
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(capability, forKey: .capability)
    try container.encode(inputs, forKey: .inputs)
    try container.encode(outputs, forKey: .outputs)
    if !recordInputs.isEmpty { try container.encode(recordInputs, forKey: .recordInputs) }
    if !recordOutputs.isEmpty { try container.encode(recordOutputs, forKey: .recordOutputs) }
  }

  public init(id: String, capability: String, inputs: [String: String], outputs: [String: String], recordInputs: [String: String] = [:], recordOutputs: [String: String] = [:]) {
    self.id = id
    self.capability = capability
    self.inputs = inputs
    self.outputs = outputs
    self.recordInputs = recordInputs
    self.recordOutputs = recordOutputs
  }
}

extension UIDocument {
  func validateCalculationBindings(fields: [String: StateField], registeredCalculations: Set<String>) throws -> Set<String> {
    guard calculations.count <= 32, Set(calculations.map(\.id)).count == calculations.count else {
      throw UIError("Calculations require at most 32 unique bindings.")
    }
    var owners = [String: String]()
    var recordOwners = Set<String>()
    for binding in calculations {
      guard validIdentifier(binding.id), validIdentifier(binding.capability), registeredCalculations.contains(binding.capability),
        binding.inputs.count + binding.recordInputs.count <= 32,
        binding.recordInputs.allSatisfy({ parameter, source in validIdentifier(parameter) && records.contains(where: { $0.id == source }) }), !binding.outputs.isEmpty || !binding.recordOutputs.isEmpty,
        binding.outputs.count + binding.recordOutputs.count <= 32,
        binding.recordOutputs.allSatisfy({ validIdentifier($0.key) && validIdentifier($0.value) }) else {
        throw UIError("Calculation requires a valid registered capability and bounded bindings.")
      }
      for mapping in [binding.inputs, binding.outputs] {
        guard mapping.allSatisfy({ validIdentifier($0.key) && fields[$0.value] != nil }) else {
          throw UIError("Calculation references an unknown field or invalid parameter.")
        }
      }
      for collection in binding.recordOutputs.values {
        guard !records.contains(where: { $0.id == collection }), recordOwners.insert(collection).inserted else {
          throw UIError("A record collection requires one calculation owner.")
        }
      }
      for field in binding.outputs.values {
        guard owners.updateValue(binding.id, forKey: field) == nil else {
          throw UIError("A derived field must have exactly one calculation owner.")
        }
      }
    }
    guard records.count + recordOwners.count <= 16 else { throw UIError("A document permits at most 16 source and derived collections.") }
    var pending = calculations
    var finished = Set<String>()
    while !pending.isEmpty {
      guard let index = pending.firstIndex(where: { binding in
        binding.inputs.values.allSatisfy { owners[$0] == nil || finished.contains(owners[$0]!) }
      }) else { throw UIError("Calculation bindings contain a dependency cycle.") }
      finished.insert(pending.remove(at: index).id)
    }
    return Set(owners.keys)
  }
}

@MainActor struct CalculationPlan {
  let registry: CalculationRegistry
  let bindings: [CalculationBinding]
  let derivedFields: Set<String>

  init(registry: CalculationRegistry, bindings: [CalculationBinding], fields: [String: StateField], recordSchemas: [String: RecordSchema] = [:]) throws {
    guard bindings.count <= 32, Set(bindings.map(\.id)).count == bindings.count else {
      throw UIError("Calculations require at most 32 unique bindings.")
    }
    var owners = [String: String]()
    var recordOwners = Set<String>()
    for binding in bindings {
      let signature = try registry.signature(binding.capability)
      guard validIdentifier(binding.id), Set(binding.inputs.keys) == Set(signature.inputs.keys),
        Set(binding.outputs.keys) == Set(signature.outputs.keys),
        Set(binding.recordOutputs.keys) == Set(signature.recordOutputs.keys),
        Set(binding.recordInputs.keys) == Set(signature.recordInputs.keys) else {
        throw UIError("Calculation binding does not match its signature.")
      }
      for (parameters, kinds) in [(binding.inputs, signature.inputs), (binding.outputs, signature.outputs)] {
        for (parameter, id) in parameters {
          guard let field = fields[id], let kind = kinds[parameter], Self.matches(field.kind, kind) else {
            throw UIError("Calculation binding has an unknown or incompatible field.")
          }
        }
      }
      for (parameter, constraint) in signature.inputNumberConstraints {
        guard let id = binding.inputs[parameter], let field = fields[id] else {
          throw UIError("Numeric constraint requires a bound input field.")
        }
        try constraint.validate(field: field)
      }
      for (parameter, collection) in binding.recordInputs {
        guard let declared = recordSchemas[collection], let expected = signature.recordInputs[parameter], declared.fields == expected.fields else {
          throw UIError("Calculation record input has an incompatible schema.")
        }
      }
      for id in binding.recordOutputs.values {
        guard validIdentifier(id), recordSchemas[id] == nil, recordOwners.insert(id).inserted else {
          throw UIError("A record collection requires one valid calculation owner.")
        }
      }
      for id in binding.outputs.values {
        guard owners.updateValue(binding.id, forKey: id) == nil else {
          throw UIError("A derived field must have exactly one calculation owner.")
        }
      }
    }
    guard recordSchemas.count + recordOwners.count <= 16 else { throw UIError("A document permits at most 16 source and derived collections.") }
    var ordered = [CalculationBinding]()
    var remaining = bindings
    var finished = Set<String>()
    while !remaining.isEmpty {
      guard let index = remaining.firstIndex(where: { binding in
        binding.inputs.values.allSatisfy { owners[$0] == nil || finished.contains(owners[$0]!) }
      }) else { throw UIError("Calculation bindings contain a dependency cycle.") }
      let next = remaining.remove(at: index)
      ordered.append(next)
      finished.insert(next.id)
    }
    self.registry = registry
    self.bindings = ordered
    self.derivedFields = Set(owners.keys)
  }

  func evaluate(_ values: [String: StateValue], fields: [String: StateField], inputRecords: [String: [RecordRow]] = [:]) throws -> CalculationResult {
    var candidate = values
    var records = inputRecords
    for binding in bindings {
      let inputs = Dictionary(uniqueKeysWithValues: binding.inputs.map { ($0.key, candidate[$0.value]!) })
      let recordInputs = Dictionary(uniqueKeysWithValues: binding.recordInputs.map { ($0.key, inputRecords[$0.value]!) })
      let result = try registry.evaluate(binding.capability, inputs: inputs, records: recordInputs)
      for (parameter, collection) in binding.recordOutputs { records[collection] = result.records[parameter]! }
      for (parameter, fieldID) in binding.outputs {
        let value = result.values[parameter]!
        try fields[fieldID]!.validate(value)
        candidate[fieldID] = value
      }
    }
    return CalculationResult(values: candidate, records: records)
  }

  private static func matches(_ field: StateField.Kind, _ kind: CalculationRegistry.ValueKind) -> Bool {
    switch (field, kind) {
    case (.number, .number), (.boolean, .boolean), (.text, .text), (.choice, .text), (.date, .text), (.date, .instant): true
    default: false
    }
  }
}
