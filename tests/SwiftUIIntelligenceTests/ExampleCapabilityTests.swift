import Foundation
import Testing
import SwiftUIIntelligence
import SwiftUIIntelligenceExamples

@Test @MainActor func exampleSignaturesDeclareRecordReferenceTargets() throws {
  let registry = try ExampleCalculations.registry()
  let comparison = try #require(registry.signatures.first { $0.id == "compare-records" })
  #expect(comparison.recordReferences.contains { $0.input == "measurements" && $0.field == "productID" && $0.targetInput == "products" })
  let bill = try #require(registry.signatures.first { $0.id == "split-bill" })
  #expect(bill.recordReferences.contains { $0.input == "assignments" && $0.field == "itemID" && $0.targetInput == "items" })
  #expect(bill.recordReferences.contains { $0.input == "assignments" && $0.field == "personID" && $0.targetInput == "people" })
}

@Test @MainActor func registeredComparisonUsesUnconfiguredFieldsAndSelection() throws {
  let registry = try ExampleCalculations.registry()
  let result = try registry.evaluate("compare-records", inputs: [:], records: [
    "products": [
      .init(id: "oak", values: ["name": .text("Oak"), "selected": .boolean(true)]),
      .init(id: "cork", values: ["name": .text("Cork"), "selected": .boolean(true)])
    ],
    "measurements": [
      .init(id: "oak-density", values: ["productID": .text("oak"), "field": .text("density"), "value": .number(750)]),
      .init(id: "cork-density", values: ["productID": .text("cork"), "field": .text("density"), "value": .number(240)])
    ],
    "conditions": [.init(id: "density-limit", values: ["field": .text("density"), "minimum": .number(0), "maximum": .number(300)])]
  ])
  #expect(result.records["matches"]?.map(\.id) == ["cork"])
  #expect(result.records["matches"]?.first?.values["selected"] == .boolean(true))
  #expect(result.records["measurements"]?.first?.values["value"] == .number(240))
  #expect(result.records["measurements"]?.first?.values["productID"] == .text("cork"))
}

@Test @MainActor func comparisonPreservesDistinctProductsWithDuplicateNames() throws {
  let registry = try ExampleCalculations.registry()
  let result = try registry.evaluate("compare-records", inputs: [:], records: [
    "products": ["one", "two"].map { .init(id: $0, values: ["name": .text("Same name"), "selected": .boolean(false)]) },
    "measurements": [
      .init(id: "measurement-a", values: ["productID": .text("one"), "field": .text("density"), "value": .number(10)]),
      .init(id: "measurement-b", values: ["productID": .text("two"), "field": .text("density"), "value": .number(20)])
    ], "conditions": []
  ])
  #expect(result.records["measurements"]?.map { $0.values["productID"] } == [.text("one"), .text("two")])
  #expect(result.records["measurements"]?.map { $0.values["name"] } == [.text("Same name"), .text("Same name")])
}

@Test @MainActor func billShareIdentitySurvivesParticipationChanges() throws {
  let registry = try ExampleCalculations.registry()
  let people: [RecordRow] = ["a", "b"].map { .init(id: $0, values: ["name": .text($0)]) }
  let items: [RecordRow] = ["x", "y"].map { .init(id: $0, values: ["name": .text($0), "amountMinor": .number(10)]) }
  func assignments(_ includeAX: Bool) -> [RecordRow] {
    [RecordRow(id: "ax", values: ["itemID": .text("x"), "personID": .text("a"), "included": .boolean(includeAX)]),
     RecordRow(id: "bx", values: ["itemID": .text("x"), "personID": .text("b"), "included": .boolean(true)]),
     RecordRow(id: "ay", values: ["itemID": .text("y"), "personID": .text("a"), "included": .boolean(true)])]
  }
  let before = try registry.evaluate("split-bill", inputs: ["feeMinor": .number(0)], records: ["people": people, "items": items, "assignments": assignments(true)])
  let after = try registry.evaluate("split-bill", inputs: ["feeMinor": .number(0)], records: ["people": people, "items": items, "assignments": assignments(false)])
  let old = before.records["shares"]?.first { $0.values["personID"] == .text("a") && $0.values["itemID"] == .text("y") }
  let current = after.records["shares"]?.first { $0.values["personID"] == .text("a") && $0.values["itemID"] == .text("y") }
  #expect(old?.id == current?.id)
  #expect(current?.id == "ay")
}

@Test @MainActor func registeredBillCapabilityReturnsExactPersonalTotals() throws {
  let registry = try ExampleCalculations.registry()
  let records: [String: [RecordRow]] = [
    "people": ["a", "b", "c"].map { .init(id: $0, values: ["name": .text($0)]) },
    "items": [.init(id: "meal", values: ["name": .text("Meal"), "amountMinor": .number(5)])],
    "assignments": ["a", "b", "c"].map { .init(id: "meal-\($0)", values: ["itemID": .text("meal"), "personID": .text($0), "included": .boolean(true)]) }
  ]
  let result = try registry.evaluate("split-bill", inputs: ["feeMinor": .number(2)], records: records)
  #expect(result.records["breakdown"]?.map { $0.values["totalMinor"] } == [.number(3), .number(3), .number(1)])
  #expect(result.values["payableMinor"] == .number(7))
  #expect(result.records["shares"]?.map { $0.values["amountMinor"] } == [.number(2), .number(2), .number(1)])
  #expect(result.records["shares"]?.map { $0.values["personID"] } == [.text("a"), .text("b"), .text("c")])
}

@Test @MainActor func billCapabilityRejectsFractionalMoneyAndUnknownParticipants() throws {
  let registry = try ExampleCalculations.registry()
  for (amount, person) in [(1.5, "a"), (1.0, "missing")] {
    let records: [String: [RecordRow]] = [
      "people": [.init(id: "a", values: ["name": .text("Ada")])],
      "items": [.init(id: "tea", values: ["name": .text("Tea"), "amountMinor": .number(amount)])],
      "assignments": [.init(id: "tea-a", values: ["itemID": .text("tea"), "personID": .text(person), "included": .boolean(true)])]
    ]
    #expect(throws: UIError.self) { try registry.evaluate("split-bill", inputs: ["feeMinor": .number(0)], records: records) }
  }
}

@Test @MainActor func mealCapabilityPreservesMaximumLengthIngredientNames() throws {
  let registry = try ExampleCalculations.registry()
  let name = String(repeating: "x", count: 1000)
  let result = try registry.evaluate("meal-plan", inputs: ["basePeople": .number(2), "people": .number(2),
    "mealTime": .text("2026-10-15T19:00:00Z")], records: [
      "ingredients": [.init(id: "ingredient", values: ["name": .text(name), "quantity": .number(1), "unit": .text("g")])],
      "steps": []
    ])
  #expect(result.records["shopping"]?.first?.values["name"] == .text(name))
  #expect(result.records["shopping"]?.first?.values["quantity"] == .number(1))
  #expect(result.records["shopping"]?.first?.values["unit"] == .text("g"))
}

@Test @MainActor func registeredMealCapabilityRecalculatesIngredientsAndSchedule() throws {
  let registry = try ExampleCalculations.registry()
  let instant = "2026-10-15T19:00:00Z"
  let records: [String: [RecordRow]] = [
    "ingredients": [.init(id: "lentils", values: ["name": .text("Lentils"), "quantity": .number(200), "unit": .text("g")])],
    "steps": [.init(id: "cook", values: ["title": .text("Cook lentils"), "minutes": .number(30)])]
  ]
  let result = try registry.evaluate("meal-plan", inputs: ["basePeople": .number(2), "people": .number(3), "mealTime": .text(instant)], records: records)
  #expect(result.records["shopping"]?.first?.values["quantity"] == .number(300))
  #expect(result.records["schedule"]?.first?.values["start"] == .text("2026-10-15T18:30:00Z"))
  let changed = try registry.evaluate("meal-plan", inputs: ["basePeople": .number(2), "people": .number(5), "mealTime": .text("2026-10-15T20:00:00Z")], records: records)
  #expect(changed.records["shopping"]?.first?.values["quantity"] == .number(500))
  #expect(changed.records["schedule"]?.first?.values["start"] == .text("2026-10-15T19:30:00Z"))
}
