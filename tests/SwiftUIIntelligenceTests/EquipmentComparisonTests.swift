import Testing
import SwiftUIIntelligenceExamples

// Given numeric constraints, filtering retains complete records and only visible selected IDs.
@Test func equipmentFiltersAndRetainsVisibleSelections() throws {
  let rows: [EquipmentComparison.Record] = [
    .init(id: "c", name: "Third", fields: ["reach": 9, "load": 5]),
    .init(id: "a", name: "First", fields: ["reach": 4, "load": 2]),
    .init(id: "b", name: "Second", fields: ["reach": 7, "load": 3]),
  ]
  let result = try EquipmentComparison.compare(.init(records: rows, constraints: [
    .init(field: "reach", minimum: 7),
    .init(field: "load", maximum: 5),
  ], selectedIDs: ["a", "b", "c"]))
  #expect(result.records == [rows[0], rows[2]])
  #expect(result.selectedIDs == ["b", "c"])
  let changed = try EquipmentComparison.compare(.init(records: rows, constraints: [
    .init(field: "load", minimum: 3, maximum: 3),
  ], selectedIDs: result.selectedIDs))
  #expect(changed.records == [rows[2]])
  #expect(changed.selectedIDs == ["b"])
}

// Given new categories and numeric fields, the same calculation uses only caller-supplied data.
@Test func equipmentAcceptsMaterialsAndBatteries() throws {
  for (name, field) in [("Aerogel", "conductivity"), ("Sodium cell", "cycleCount")] {
    let rows: [EquipmentComparison.Record] = [
      .init(id: "new-1", name: name, fields: [field: -2.5, "custom": 12]),
      .init(id: "new-2", name: "Alternative", fields: [field: 8, "custom": 0]),
    ]
    let result = try EquipmentComparison.compare(.init(records: rows, constraints: [
      .init(field: field, minimum: -3, maximum: 0),
    ], selectedIDs: ["new-1"]))
    #expect(result.records == [rows[0]])
    #expect(result.selectedIDs == ["new-1"])
  }
}

// Given empty input or no matches, the result is empty; absent constraints preserve all rows.
@Test func equipmentHandlesEmptyAndUnconstrainedResults() throws {
  let empty = try EquipmentComparison.compare(.init(records: [], constraints: [], selectedIDs: []))
  #expect(empty.records.isEmpty)
  #expect(empty.selectedIDs.isEmpty)
  let row = EquipmentComparison.Record(id: "r", name: "Record", fields: ["level": 1])
  let unchanged = try EquipmentComparison.compare(.init(records: [row], constraints: [], selectedIDs: ["r"]))
  #expect(unchanged.records == [row])
  #expect(unchanged.selectedIDs == ["r"])
  let filtered = try EquipmentComparison.compare(.init(records: [row], constraints: [
    .init(field: "level", minimum: 2),
  ], selectedIDs: ["r"]))
  #expect(filtered.records.isEmpty)
  #expect(filtered.selectedIDs.isEmpty)
}

// Given invalid IDs, bounds, or field references, validation rejects the entire input before filtering.
@Test func equipmentRejectsInvalidInput() {
  typealias Input = EquipmentComparison.Input
  typealias Failure = EquipmentComparison.ComparisonError
  let row = EquipmentComparison.Record(id: "r", name: "Record", fields: ["x": 1])
  let cases: [(Input, Failure)] = [
    (.init(records: [row, row], constraints: [], selectedIDs: []), .duplicateID("r")),
    (.init(records: [.init(id: "", name: "Empty ID", fields: [:])], constraints: [], selectedIDs: []), .invalidID),
    (.init(records: [.init(id: "r", name: "", fields: [:])], constraints: [], selectedIDs: []), .invalidName("r")),
    (.init(records: [row], constraints: [], selectedIDs: ["unknown"]), .unknownSelectedID("unknown")),
    (.init(records: [], constraints: [], selectedIDs: ["r"]), .unknownSelectedID("r")),
    (.init(records: [row], constraints: [.init(field: "missing")], selectedIDs: []), .unknownField("missing")),
    (.init(records: [], constraints: [.init(field: "x")], selectedIDs: []), .unknownField("x")),
    (.init(records: [row, .init(id: "other", name: "Other", fields: [:])],
      constraints: [.init(field: "x", minimum: 100)], selectedIDs: []), .missingField(recordID: "other", field: "x")),
    (.init(records: [row], constraints: [.init(field: "x", minimum: 2, maximum: 1)], selectedIDs: []), .invalidConstraint("x")),
    (.init(records: [.init(id: "r", name: "Record", fields: ["": 1])], constraints: [], selectedIDs: []), .invalidField),
  ]
  for (input, error) in cases {
    #expect(throws: error) { try EquipmentComparison.compare(input) }
  }
  for value in [Double.nan, .infinity, -.infinity, 1_000_000_001, -1_000_000_001] {
    #expect(throws: Failure.invalidValue(recordID: "r", field: "x")) {
      try EquipmentComparison.compare(.init(records: [.init(id: "r", name: "Record", fields: ["x": value])],
        constraints: [], selectedIDs: []))
    }
    for constraint in [EquipmentComparison.Constraint(field: "x", minimum: value),
      EquipmentComparison.Constraint(field: "x", maximum: value)] {
      #expect(throws: Failure.invalidConstraint("x")) {
        try EquipmentComparison.compare(.init(records: [row], constraints: [constraint], selectedIDs: []))
      }
    }
  }
}

// Given bounded collections, exact limits pass and excess rows or distinct fields fail.
@Test func equipmentEnforcesCollectionLimits() throws {
  let fields = Dictionary(uniqueKeysWithValues: (0..<16).map { ("field-\($0)", Double($0)) })
  let rows = (0..<32).map { EquipmentComparison.Record(id: "id-\($0)", name: "Record \($0)", fields: fields) }
  let result = try EquipmentComparison.compare(.init(records: rows, constraints: [], selectedIDs: ["id-31"]))
  #expect(result.records == rows)
  #expect(result.selectedIDs == ["id-31"])
  #expect(throws: EquipmentComparison.ComparisonError.tooManyRecords) {
    try EquipmentComparison.compare(.init(records: rows + [.init(id: "extra", name: "Extra", fields: [:])],
      constraints: [], selectedIDs: []))
  }
  #expect(throws: EquipmentComparison.ComparisonError.tooManyFields) {
    try EquipmentComparison.compare(.init(records: [rows[0], .init(id: "extra", name: "Extra", fields: ["seventeenth": 0])],
      constraints: [], selectedIDs: []))
  }
  let boundary = EquipmentComparison.Record(id: "edge", name: "Boundary", fields: ["low": -1e9, "high": 1e9])
  let bounded = try EquipmentComparison.compare(.init(records: [boundary], constraints: [
    .init(field: "low", minimum: -1e9), .init(field: "high", maximum: 1e9),
  ], selectedIDs: []))
  #expect(bounded.records == [boundary])
}
