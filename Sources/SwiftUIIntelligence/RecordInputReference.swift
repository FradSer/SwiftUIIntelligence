import Foundation

/// A host-declared text field whose values identify rows in another record input.
public struct RecordInputReference: Codable, Sendable {
  public let input: String
  public let field: String
  public let targetInput: String

  public init(input: String, field: String, targetInput: String) {
    self.input = input
    self.field = field
    self.targetInput = targetInput
  }

  private enum CodingKeys: String, CodingKey { case input, field, targetInput }
  public init(from decoder: any Decoder) throws {
    try checkKeys(decoder, allowed: ["input", "field", "targetInput"])
    let container = try decoder.container(keyedBy: CodingKeys.self)
    input = try container.decode(String.self, forKey: .input)
    field = try container.decode(String.self, forKey: .field)
    targetInput = try container.decode(String.self, forKey: .targetInput)
  }

  static func validateSchemas(_ references: [Self], inputs: [String: RecordSchema]) throws {
    var sourceFields: [String: Set<String>] = [:]
    var dependencies: [String: Set<String>] = [:]
    for reference in references {
      guard validIdentifier(reference.input), validIdentifier(reference.field), validIdentifier(reference.targetInput),
        inputs[reference.input]?.fields[reference.field] == .text, inputs[reference.targetInput] != nil,
        sourceFields[reference.input, default: []].insert(reference.field).inserted else {
        throw UIError("Invalid record input reference.")
      }
      dependencies[reference.input, default: []].insert(reference.targetInput)
    }
    var visiting: Set<String> = []
    var visited: Set<String> = []
    func visit(_ input: String) throws {
      guard !visiting.contains(input) else { throw UIError("Record input references must not contain cycles.") }
      guard !visited.contains(input) else { return }
      visiting.insert(input)
      for target in dependencies[input, default: []] { try visit(target) }
      visiting.remove(input)
      visited.insert(input)
    }
    for input in dependencies.keys { try visit(input) }
  }

  static func validateValues(_ references: [Self], records: [String: [RecordRow]]) throws {
    for reference in references {
      guard let source = records[reference.input], let target = records[reference.targetInput] else {
        throw UIError("Missing record input for reference.")
      }
      let targetIDs = Set(target.map(\.id))
      for row in source {
        guard case .text(let id) = row.values[reference.field], targetIDs.contains(id) else {
          throw UIError("Record input reference must identify an existing target row.")
        }
      }
    }
  }
}
