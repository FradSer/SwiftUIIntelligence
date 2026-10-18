import Foundation
import Testing
import SwiftUIIntelligence
import SwiftUIIntelligenceExamples
import InteractionFixtureSupport

// Synthetic acceptance fixtures only. These are not page-generation templates.
// Given remapped IDs and either chart orientation, the generic interactive layout passes.
@Test @MainActor func equipmentInteractionAcceptsRemappedLayouts() throws {
  for prefix in ["alpha", "zulu"] {
    for fields in [["name", "value", "field"], ["field", "value", "name"]] {
      for title in ["Price (USD) and weight (g)", "Price in USD / Weight in grams", "Price (USD), Weight (gram)", "USD price / grams weight"] {
        var source = InteractionFixtures.equipment(prefix: prefix, chartFields: fields)
        var root = source["root"] as! [String: Any]
        var children = root["children"] as! [[String: Any]]
        children[4]["title"] = title
        var columns = children[1]["columns"] as! [String]
        columns[0] = "Price and weight conditions"
        children[1]["columns"] = columns
        root["children"] = children
        source["root"] = root
        try EquipmentInteractionAcceptance.validate(equipmentDocument(source), registry: ExampleCalculations.registry())
      }
    }
  }
}

// Given correct source facts, a text root is not an interactive comparison.
@Test @MainActor func equipmentInteractionRejectsSourceOnlyRoot() throws {
  var source = InteractionFixtures.equipment()
  source["root"] = ["id": "plain", "type": "text", "text": "Equipment USD grams"]
  let document = try equipmentDocument(source)
  try ExampleAcceptance.validate(document, example: .equipment)
  #expect(throws: UIError.self) {
    try EquipmentInteractionAcceptance.validate(document, registry: ExampleCalculations.registry())
  }
}

// Given valid sources, wrong sources, static outputs, absent editors, and unrelated charts fail.
@Test @MainActor func equipmentInteractionRejectsIncompleteLayout() throws {
  let mutations: [(inout [[String: Any]]) -> Void] = [
    { $0[0]["editableFields"] = [String]() },
    { $0[1]["editableFields"] = ["minimum"] },
    { $0[2]["recordSource"] = "mapped-products" },
    { $0[3] = ["id": "static", "type": "table", "columns": ["Name"], "rows": [["Cedar"]]] },
    { $0[4].removeValue(forKey: "recordSource"); $0[4].removeValue(forKey: "recordFields") },
    { $0[4]["recordSource"] = "mapped-measurements"; $0[4]["recordFields"] = ["productID", "value", "field"] },
    { $0[4]["title"] = "Price and weight" },
    { $0[4]["title"] = "Price (g) and weight (USD)" },
    {
      $0[4]["title"] = "Price (g) and weight (USD)"
      $0.append(["id": "unrelated", "type": "text", "text": "USD prices and grams elsewhere"])
    },
    {
      $0[4]["title"] = "Price and weight"
      $0.append(["id": "unrelated", "type": "text", "text": "Price (USD), weight (grams)"])
    },
    { $0[4]["title"] = "Price (USD) and weight (USD), g" },
    { $0[4]["title"] = "Price (g) USD and weight (grams)" },
    { $0.removeLast() },
  ]
  for mutate in mutations {
    var source = InteractionFixtures.equipment()
    var root = source["root"] as! [String: Any]
    var children = root["children"] as! [[String: Any]]
    mutate(&children)
    root["children"] = children
    source["root"] = root
    let document = try equipmentDocument(source)
    let registry = try ExampleCalculations.registry()
    try document.validate(registeredActions: [], registeredCalculations: registry.names)
    #expect(throws: UIError.self) { try EquipmentInteractionAcceptance.validate(document, registry: registry) }
  }
}

// Given a complete layout, incorrect selection, measurement, filtering, or restore behavior fails.
@Test @MainActor func equipmentInteractionRejectsIncorrectRegistry() throws {
  let good = try ExampleCalculations.registry()
  let signature = try #require(good.signatures.first { $0.id == "compare-records" })
  for failure in ["selection", "latched-selection", "price-minimum", "weight-minimum", "value", "identity", "empty", "restore"] {
    var sawEmpty = false
    var selectedIDs = Set<String>()
    let bad = try CalculationRegistry([.init(id: signature.id, inputs: signature.inputs, outputs: signature.outputs,
      recordInputs: signature.recordInputs, recordOutputs: signature.recordOutputs) { values, records in
        // Given preserved source values, ignoring either minimum or latching a true
        // selection must fail when the isolated acceptance edits that input.
        var inputs = records
        if failure == "price-minimum" || failure == "weight-minimum" {
          let field = failure == "price-minimum" ? "price" : "weight"
          inputs["conditions"] = records["conditions"]!.map { row in
            var fields = row.values
            if fields["field"] == .text(field) { fields["minimum"] = .number(0) }
            return RecordRow(id: row.id, values: fields)
          }
        }
        if failure == "latched-selection" {
          inputs["products"] = records["products"]!.map { row in
            var fields = row.values
            if fields["selected"] == .boolean(true) { selectedIDs.insert(row.id) }
            fields["selected"] = .boolean(selectedIDs.contains(row.id))
            return RecordRow(id: row.id, values: fields)
          }
        }
        let result = try good.evaluate("compare-records", inputs: values, records: inputs)
        var outputs = result.records
        let empty = outputs["matches"]!.isEmpty
        if empty { sawEmpty = true }
        if failure == "empty" && empty {
          var initial = records
          initial["conditions"] = records["conditions"]!.map { row in
            var fields = row.values
            fields["maximum"] = fields["field"] == .text("price") ? .number(130) : .number(1300)
            return RecordRow(id: row.id, values: fields)
          }
          return try good.evaluate("compare-records", inputs: values, records: initial)
        }
        if failure == "restore" && sawEmpty && !empty { outputs["measurements"] = [] }
        if failure == "selection" {
          outputs["matches"] = outputs["matches"]!.map { row in
            var fields = row.values; fields["selected"] = .boolean(false)
            return RecordRow(id: row.id, values: fields)
          }
        }
        if failure == "value" || failure == "identity" {
          outputs["measurements"] = outputs["measurements"]!.map { row in
            var fields = row.values
            fields[failure == "value" ? "value" : "productID"] = failure == "value" ? .number(1) : .text("unknown")
            return RecordRow(id: row.id, values: fields)
          }
        }
        return CalculationResult(values: result.values, records: outputs)
      }])
    #expect(throws: UIError.self) {
      try EquipmentInteractionAcceptance.validate(equipmentDocument(InteractionFixtures.equipment()), registry: bad)
    }
  }
}

private func equipmentDocument(_ source: [String: Any]) throws -> UIDocument {
  try JSONDecoder().decode(UIDocument.self, from: JSONSerialization.data(withJSONObject: source))
}
