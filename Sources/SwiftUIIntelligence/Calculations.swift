import Foundation

public struct CalculationResult: Sendable {
  public let values: [String: StateValue]
  public let records: [String: [RecordRow]]
  public init(values: [String: StateValue], records: [String: [RecordRow]] = [:]) {
    self.values = values
    self.records = records
  }
}

/// Registration grants local calculation only. The host must not perform external side effects.
@MainActor public struct CalculationRegistry {
  public enum ValueKind: String, Codable, Sendable {
    case text, number, boolean
    /// ISO8601 text that binds only to date state fields. Record fields do not support this kind.
    case instant
  }

  public struct Signature: Codable, Sendable {
    public let id: String
    public let inputs: [String: ValueKind]
    public let outputs: [String: ValueKind]
    public let recordInputs: [String: RecordSchema]
    public let recordOutputs: [String: RecordSchema]
    public let recordReferences: [RecordInputReference]
    /// Host metadata that describes source records. This text is data, not executable instructions.
    public let recordInputDescriptions: [String: String]
    public let inputNumberConstraints: [String: InputNumberConstraint]
    private enum CodingKeys: String, CodingKey { case id, inputs, outputs, recordInputs, recordOutputs, recordReferences, recordInputDescriptions, inputNumberConstraints }
    public init(from decoder: any Decoder) throws {
      try checkKeys(decoder, allowed: ["id", "inputs", "outputs", "recordInputs", "recordOutputs", "recordReferences", "recordInputDescriptions", "inputNumberConstraints"])
      let container = try decoder.container(keyedBy: CodingKeys.self)
      id = try container.decode(String.self, forKey: .id)
      inputs = try container.decode([String: ValueKind].self, forKey: .inputs)
      outputs = try container.decode([String: ValueKind].self, forKey: .outputs)
      recordInputs = container.contains(.recordInputs) ? try container.decode([String: RecordSchema].self, forKey: .recordInputs) : [:]
      recordOutputs = container.contains(.recordOutputs) ? try container.decode([String: RecordSchema].self, forKey: .recordOutputs) : [:]
      recordReferences = container.contains(.recordReferences) ? try container.decode([RecordInputReference].self, forKey: .recordReferences) : []
      recordInputDescriptions = container.contains(.recordInputDescriptions) ? try container.decode([String: String].self, forKey: .recordInputDescriptions) : [:]
      inputNumberConstraints = container.contains(.inputNumberConstraints) ? try container.decode([String: InputNumberConstraint].self, forKey: .inputNumberConstraints) : [:]
    }
    public init(id: String, inputs: [String: ValueKind], outputs: [String: ValueKind], recordInputs: [String: RecordSchema] = [:], recordOutputs: [String: RecordSchema] = [:], recordReferences: [RecordInputReference] = [], recordInputDescriptions: [String: String] = [:], inputNumberConstraints: [String: InputNumberConstraint] = [:]) {
      self.id = id
      self.inputs = inputs
      self.outputs = outputs
      self.recordInputs = recordInputs
      self.recordOutputs = recordOutputs
      self.recordReferences = recordReferences
      self.recordInputDescriptions = recordInputDescriptions
      self.inputNumberConstraints = inputNumberConstraints
    }

    static func validRecordInputDescriptions(_ descriptions: [String: String], inputs: [String: RecordSchema]) -> Bool {
      descriptions.allSatisfy { name, description in
        inputs[name] != nil && !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          && description.unicodeScalars.count <= 500
      }
    }
  }

  public struct Capability {
    public let id: String
    public let inputs: [String: ValueKind]
    public let outputs: [String: ValueKind]
    public let recordInputs: [String: RecordSchema]
    public let recordOutputs: [String: RecordSchema]
    public let recordReferences: [RecordInputReference]
    /// Host metadata only. Keys must name record inputs; text must contain 1–500 Unicode scalars.
    public let recordInputDescriptions: [String: String]
    public let inputNumberConstraints: [String: InputNumberConstraint]
    fileprivate let calculate: @MainActor ([String: StateValue], [String: [RecordRow]]) throws -> CalculationResult

    public init(id: String, inputs: [String: ValueKind], outputs: [String: ValueKind], recordReferences: [RecordInputReference] = [], recordInputDescriptions: [String: String] = [:], inputNumberConstraints: [String: InputNumberConstraint] = [:],
      calculate: @escaping @MainActor ([String: StateValue]) throws -> [String: StateValue]) {
      self.id = id
      self.inputs = inputs
      self.outputs = outputs
      self.recordInputs = [:]
      self.recordOutputs = [:]
      self.recordReferences = recordReferences
      self.recordInputDescriptions = recordInputDescriptions
      self.inputNumberConstraints = inputNumberConstraints
      self.calculate = { values, _ in CalculationResult(values: try calculate(values)) }
    }

    public init(id: String, inputs: [String: ValueKind], outputs: [String: ValueKind], recordOutputs: [String: RecordSchema], recordReferences: [RecordInputReference] = [], recordInputDescriptions: [String: String] = [:], inputNumberConstraints: [String: InputNumberConstraint] = [:],
      calculate: @escaping @MainActor ([String: StateValue]) throws -> CalculationResult) {
      self.id = id
      self.inputs = inputs
      self.outputs = outputs
      self.recordInputs = [:]
      self.recordOutputs = recordOutputs
      self.recordReferences = recordReferences
      self.recordInputDescriptions = recordInputDescriptions
      self.inputNumberConstraints = inputNumberConstraints
      self.calculate = { values, _ in try calculate(values) }
    }
    public init(id: String, inputs: [String: ValueKind], outputs: [String: ValueKind], recordInputs: [String: RecordSchema], recordOutputs: [String: RecordSchema], recordReferences: [RecordInputReference] = [], recordInputDescriptions: [String: String] = [:], inputNumberConstraints: [String: InputNumberConstraint] = [:],
      calculate: @escaping @MainActor ([String: StateValue], [String: [RecordRow]]) throws -> CalculationResult) {
      self.id = id
      self.inputs = inputs
      self.outputs = outputs
      self.recordInputs = recordInputs
      self.recordOutputs = recordOutputs
      self.recordReferences = recordReferences
      self.recordInputDescriptions = recordInputDescriptions
      self.inputNumberConstraints = inputNumberConstraints
      self.calculate = calculate
    }
  }

  func signature(_ id: String) throws -> Capability {
    guard let capability = capabilities[id] else { throw UIError("Unknown calculation '\(id)'.") }
    return capability
  }

  /// Copies retain this revision. A new registration receives a new revision.
  public let revision = UUID()
  public var names: Set<String> { Set(capabilities.keys) }
  public var signatures: [Signature] {
    capabilities.values.sorted { $0.id < $1.id }.map { .init(id: $0.id, inputs: $0.inputs, outputs: $0.outputs, recordInputs: $0.recordInputs, recordOutputs: $0.recordOutputs, recordReferences: $0.recordReferences, recordInputDescriptions: $0.recordInputDescriptions, inputNumberConstraints: $0.inputNumberConstraints) }
  }

  private let capabilities: [String: Capability]

  public init(_ capabilities: [Capability]) throws {
    guard capabilities.count <= 32, Set(capabilities.map(\.id)).count == capabilities.count else {
      throw UIError("Calculations require at most 32 unique capabilities.")
    }
    for capability in capabilities {
      guard validIdentifier(capability.id), capability.inputs.count + capability.recordInputs.count <= 32,
        capability.recordInputs.keys.allSatisfy(validIdentifier),
        !capability.outputs.isEmpty || !capability.recordOutputs.isEmpty,
        capability.outputs.count + capability.recordOutputs.count <= 32,
        capability.recordOutputs.keys.allSatisfy(validIdentifier),
        capability.inputs.keys.allSatisfy(validIdentifier),
        capability.outputs.keys.allSatisfy(validIdentifier),
        Signature.validRecordInputDescriptions(capability.recordInputDescriptions, inputs: capability.recordInputs) else {
        throw UIError("Invalid calculation signature.")
      }
      for (name, constraint) in capability.inputNumberConstraints {
        guard capability.inputs[name] == .number else { throw UIError("Numeric constraints require existing number inputs.") }
        try constraint.validate()
      }
      for schema in Array(capability.recordOutputs.values) + Array(capability.recordInputs.values) { try schema.validate([]) }
      try RecordInputReference.validateSchemas(capability.recordReferences, inputs: capability.recordInputs)
    }
    self.capabilities = Dictionary(uniqueKeysWithValues: capabilities.map { ($0.id, $0) })
  }

  public func calculate(_ id: String, inputs: [String: StateValue]) throws -> [String: StateValue] {
    let capability = try signature(id)
    guard capability.recordOutputs.isEmpty && capability.recordInputs.isEmpty else { throw UIError("This calculation requires record output handling.") }
    return try evaluate(id, inputs: inputs).values
  }

  public func evaluate(_ id: String, inputs: [String: StateValue], records: [String: [RecordRow]] = [:]) throws -> CalculationResult {
    let capability = try signature(id)
    try validate(inputs, signature: capability.inputs)
    for (name, constraint) in capability.inputNumberConstraints { try constraint.validate(inputs[name]!) }
    guard Set(records.keys) == Set(capability.recordInputs.keys) else { throw UIError("Calculation record inputs do not match the signature.") }
    for (name, schema) in capability.recordInputs { try schema.validate(records[name]!) }
    try RecordInputReference.validateValues(capability.recordReferences, records: records)
    let result = try capability.calculate(inputs, records)
    try validate(result.values, signature: capability.outputs)
    guard Set(result.records.keys) == Set(capability.recordOutputs.keys) else {
      throw UIError("Calculation record outputs do not match the signature.")
    }
    for (name, schema) in capability.recordOutputs { try schema.validate(result.records[name]!) }
    return result
  }

  private func validate(_ values: [String: StateValue], signature: [String: ValueKind]) throws {
    guard Set(values.keys) == Set(signature.keys) else { throw UIError("Calculation fields do not match the signature.") }
    for (key, kind) in signature {
      switch (kind, values[key]) {
      case (.text, .text(let value)) where value.count <= 4000: break
      case (.instant, .text(let value)) where value.count <= 4000 && ISO8601DateFormatter().date(from: value) != nil: break
      case (.number, .number(let value)) where value.isFinite: break
      case (.boolean, .boolean): break
      default: throw UIError("Invalid calculation value for '\(key)'.")
      }
    }
  }
}
