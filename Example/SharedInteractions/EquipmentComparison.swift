// Example-owned calculation. The core SDK has no equipment-specific logic.
public enum EquipmentComparison {
  public static let maximumRecords = 32
  public static let maximumFields = 16
  public static let maximumMagnitude = 1_000_000_000.0

  public struct Record: Equatable, Sendable {
    public let id: String
    public let name: String
    public let fields: [String: Double]

    public init(id: String, name: String, fields: [String: Double]) {
      self.id = id
      self.name = name
      self.fields = fields
    }
  }

  public struct Constraint: Equatable, Sendable {
    public let field: String
    public let minimum: Double?
    public let maximum: Double?

    /// Bounds are inclusive. Absent bounds only require the field to exist.
    public init(field: String, minimum: Double? = nil, maximum: Double? = nil) {
      self.field = field
      self.minimum = minimum
      self.maximum = maximum
    }
  }

  public struct Input: Equatable, Sendable {
    public let records: [Record]
    public let constraints: [Constraint]
    public let selectedIDs: Set<String>

    public init(records: [Record], constraints: [Constraint], selectedIDs: Set<String>) {
      self.records = records
      self.constraints = constraints
      self.selectedIDs = selectedIDs
    }
  }

  public struct Result: Equatable, Sendable {
    public let records: [Record]
    public let selectedIDs: Set<String>
  }

  public enum ComparisonError: Error, Equatable, Sendable {
    case tooManyRecords
    case tooManyFields
    case invalidID
    case duplicateID(String)
    case invalidName(String)
    case invalidField
    case invalidValue(recordID: String, field: String)
    case unknownSelectedID(String)
    case unknownField(String)
    case missingField(recordID: String, field: String)
    case invalidConstraint(String)
  }

  /// Validates all input before filtering. Output preserves the original records and their order.
  public static func compare(_ input: Input) throws -> Result {
    guard input.records.count <= maximumRecords else { throw ComparisonError.tooManyRecords }
    var ids = Set<String>()
    var fields = Set<String>()
    for record in input.records {
      guard !record.id.isEmpty else { throw ComparisonError.invalidID }
      guard ids.insert(record.id).inserted else { throw ComparisonError.duplicateID(record.id) }
      guard !record.name.isEmpty else { throw ComparisonError.invalidName(record.id) }
      for field in record.fields.keys.sorted() {
        guard !field.isEmpty else { throw ComparisonError.invalidField }
        fields.insert(field)
        guard fields.count <= maximumFields else { throw ComparisonError.tooManyFields }
        guard let value = record.fields[field], isValidNumber(value) else {
          throw ComparisonError.invalidValue(recordID: record.id, field: field)
        }
      }
    }
    for id in input.selectedIDs.sorted() where !ids.contains(id) {
      throw ComparisonError.unknownSelectedID(id)
    }
    for constraint in input.constraints {
      guard fields.contains(constraint.field) else { throw ComparisonError.unknownField(constraint.field) }
      if let minimum = constraint.minimum, !isValidNumber(minimum) {
        throw ComparisonError.invalidConstraint(constraint.field)
      }
      if let maximum = constraint.maximum, !isValidNumber(maximum) {
        throw ComparisonError.invalidConstraint(constraint.field)
      }
      if let minimum = constraint.minimum, let maximum = constraint.maximum, minimum > maximum {
        throw ComparisonError.invalidConstraint(constraint.field)
      }
      // Missing queried fields reject even when another constraint would exclude the record.
      for record in input.records where record.fields[constraint.field] == nil {
        throw ComparisonError.missingField(recordID: record.id, field: constraint.field)
      }
    }
    let records = input.records.filter { record in
      input.constraints.allSatisfy { constraint in
        guard let value = record.fields[constraint.field] else { return false }
        return (constraint.minimum.map { value >= $0 } ?? true)
          && (constraint.maximum.map { value <= $0 } ?? true)
      }
    }
    return Result(records: records, selectedIDs: input.selectedIDs.intersection(records.map(\.id)))
  }

  private static func isValidNumber(_ value: Double) -> Bool {
    value.isFinite && abs(value) <= maximumMagnitude
  }
}
