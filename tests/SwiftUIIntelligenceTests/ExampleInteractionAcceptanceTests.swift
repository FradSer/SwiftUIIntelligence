import Foundation
import Testing
import SwiftUIIntelligence
import SwiftUIIntelligenceExamples

// Synthetic documents test acceptance only. They are not runtime generation templates.
// A people control must permit the same single-person edits as the state probe.
@Test @MainActor func mealPeopleControlMustSupportSinglePersonChanges() throws {
  var source = mealInteractionSource()
  var fields = source["state"] as! [[String: Any]]
  fields[1]["minimum"] = 1
  fields[1]["maximum"] = 9
  fields[1]["step"] = 2
  source["state"] = fields
  let document = try mealInteractionDocument(source)
  let registry = try ExampleCalculations.registry()
  try document.validate(registeredActions: [], registeredCalculations: registry.names)
  #expect(throws: UIError.self) { try ExampleInteractionAcceptance.validateMeal(document, registry: registry) }
}

// Integer bounds keep each single-person slider change reachable.
@Test @MainActor func mealSliderRequiresIntegerAlignedBounds() throws {
  var source = mealInteractionSource()
  var fields = source["state"] as! [[String: Any]]
  fields[1]["minimum"] = 1.5
  fields[1]["maximum"] = 9.5
  fields[1]["step"] = 1
  source["state"] = fields
  var root = source["root"] as! [String: Any]
  var children = root["children"] as! [[String: Any]]
  children[0]["controlType"] = "slider"
  root["children"] = children
  source["root"] = root
  let document = try mealInteractionDocument(source)
  let registry = try ExampleCalculations.registry()
  try document.validate(registeredActions: [], registeredCalculations: registry.names)
  #expect(throws: UIError.self) { try ExampleInteractionAcceptance.validateMeal(document, registry: registry) }
}

// Given correct source facts but no editors or projections, acceptance rejects a text root.
@Test @MainActor func mealInteractionRejectsSourceOnlyDocument() throws {
  var source = mealInteractionSource()
  source["root"] = ["id": "plain", "type": "text", "text": "Meal"]
  let document = try mealInteractionDocument(source)
  try ExampleAcceptance.validate(document, example: .meal)
  #expect(throws: UIError.self) {
    try ExampleInteractionAcceptance.validateMeal(document, registry: ExampleCalculations.registry())
  }
}

// Given arbitrary IDs and nested generic nodes, acceptance checks bindings rather than page names.
@Test @MainActor func mealInteractionAcceptsGenericStructureAndRemappedIDs() throws {
  for numericControl in ["stepper", "slider"] {
    var source = mealInteractionSource()
    var root = source["root"] as! [String: Any]
    var children = root["children"] as! [[String: Any]]
    children[0]["controlType"] = numericControl
    root["children"] = [["id": "nested", "type": "section", "title": "Inputs and results", "children": children]]
    source["root"] = root
    try ExampleInteractionAcceptance.validateMeal(mealInteractionDocument(source), registry: ExampleCalculations.registry())
  }
}

// Given valid source, wrong projections, static results, and unrelated controls must not satisfy the contract.
@Test @MainActor func mealInteractionRejectsIncompleteObservableStructure() throws {
  let mutations: [(inout [[String: Any]]) -> Void] = [
    { $0[2]["recordSource"] = "raw-food" },
    { $0[2]["recordFields"] = ["name", "quantity"]; $0[2]["columns"] = ["Name", "Quantity"]; $0[2]["rows"] = [["Name", "Quantity"]] },
    { $0[3]["recordFields"] = ["title", "start", "end"] },
    { $0[3] = ["id": "static-times", "type": "timeline", "title": "Schedule", "events": [["time": "18:20", "title": "preparation", "detail": "18:30"]]] },
    { $0[0]["binding"] = "unrelated" },
    { $0[1]["binding"] = "other-date" },
    { $0.append(["id": "base-editor", "type": "control", "title": "Base", "controlType": "stepper", "binding": "original-count"]) },
    { $0[2] = ["id": "static-shopping", "type": "table", "columns": ["Name", "Quantity", "Unit"], "rows": [["lentils", "300", "g"]]] },
  ]
  for mutate in mutations {
    var source = mealInteractionSource()
    var root = source["root"] as! [String: Any]
    var children = root["children"] as! [[String: Any]]
    mutate(&children)
    root["children"] = children
    source["root"] = root
    let document = try mealInteractionDocument(source)
    let registry = try ExampleCalculations.registry()
    try document.validate(registeredActions: [], registeredCalculations: registry.names)
    let state = DocumentState()
    try state.load(document, calculations: registry)
    #expect(throws: UIError.self) {
      try ExampleInteractionAcceptance.validateMeal(document, registry: registry)
    }
  }
}

// Given a complete layout, acceptance validates the supplied registry, including edits on isolated state.
@Test @MainActor func mealInteractionRejectsIncorrectRegistryDefaultsAndCumulativeEdits() throws {
  let good = try ExampleCalculations.registry()
  let signature = try #require(good.signatures.first { $0.id == "meal-plan" })
  for failure in ["defaults", "people", "time", "restore", "schedule-order"] {
    var editedPeople = false
    let bad = try CalculationRegistry([.init(id: signature.id, inputs: signature.inputs, outputs: signature.outputs,
      recordInputs: signature.recordInputs, recordOutputs: signature.recordOutputs) { values, records in
        let result = try good.evaluate("meal-plan", inputs: values, records: records)
        if failure == "schedule-order" {
          var outputs = result.records
          outputs["schedule"] = Array(outputs["schedule"]!.reversed())
          return CalculationResult(values: result.values, records: outputs)
        }
        let restoring = editedPeople && values["people"] == .number(3)
        if values["people"] == .number(4) { editedPeople = true }
        let shifted = values["mealTime"] == .text("2026-10-15T20:00:00Z")
        if failure == "time" && shifted {
          var originalValues = values
          originalValues["mealTime"] = .text("2026-10-15T19:00:00Z")
          return try good.evaluate("meal-plan", inputs: originalValues, records: records)
        }
        if failure == "defaults" || (failure == "people" && editedPeople)
          || (failure == "restore" && restoring) {
          var outputs = result.records
          outputs["shopping"] = result.records["shopping"]!.map { row in
            var fields = row.values
            fields["quantity"] = .number(1)
            return RecordRow(id: row.id, values: fields)
          }
          return CalculationResult(values: result.values, records: outputs)
        }
        return result
      }])
    #expect(throws: UIError.self) {
      try ExampleInteractionAcceptance.validateMeal(mealInteractionDocument(mealInteractionSource()), registry: bad)
    }
  }
}

private func mealInteractionDocument(_ source: [String: Any]) throws -> UIDocument {
  try JSONDecoder().decode(UIDocument.self, from: JSONSerialization.data(withJSONObject: source))
}

private func mealInteractionSource() -> [String: Any] {
  func collection(_ id: String, fields: [String: String], values: [[String: Any]]) -> [String: Any] {
    ["id": id, "schema": ["fields": fields], "rows": values.enumerated().map { ["id": "row-\($0.offset)", "values": $0.element] }]
  }
  return [
    "version": 1,
    "state": [
      ["id": "original-count", "kind": "number", "value": 2, "minimum": 1, "maximum": MealPlanning.maximumPeople, "step": 1],
      ["id": "desired-count", "kind": "number", "value": 3, "minimum": 1, "maximum": MealPlanning.maximumPeople, "step": 1],
      ["id": "dinner-instant", "kind": "date", "value": "2026-10-15T19:00:00Z"],
      ["id": "unrelated", "kind": "number", "value": 3],
      ["id": "other-date", "kind": "date", "value": "2026-10-15T19:00:00Z"],
    ],
    "calculations": [["id": "authored-plan", "capability": "meal-plan",
      "inputs": ["basePeople": "original-count", "people": "desired-count", "mealTime": "dinner-instant"],
      "outputs": [String: String](), "recordInputs": ["ingredients": "raw-food", "steps": "raw-steps"],
      "recordOutputs": ["shopping": "computed-food", "schedule": "computed-times"]]],
    "records": [
      collection("raw-food", fields: ["name": "text", "quantity": "number", "unit": "text"], values:
        zip(["lentils", "rice", "carrots"], [200, 150, 100]).map { ["name": $0.0, "quantity": $0.1, "unit": "g"] }),
      collection("raw-steps", fields: ["title": "text", "minutes": "number"], values:
        zip(["preparation", "cooking", "serving"], [10, 25, 5]).map { ["title": $0.0, "minutes": $0.1] }),
    ],
    "root": ["id": "any-container", "type": "vstack", "children": [
      ["id": "count-editor", "type": "control", "title": "People", "controlType": "stepper", "binding": "desired-count"],
      ["id": "time-editor", "type": "control", "title": "Meal time", "controlType": "datePicker", "binding": "dinner-instant"],
      ["id": "result-table", "type": "table", "columns": ["Ingredient", "Quantity", "Unit"], "rows": [["Ingredient", "Quantity", "Unit"]], "recordSource": "computed-food", "recordFields": ["name", "quantity", "unit"]],
      ["id": "result-timeline", "type": "timeline", "title": "Schedule", "events": [["time": "Start", "title": "Step", "detail": "End"]], "recordSource": "computed-times", "recordFields": ["start", "title", "end"]],
    ]],
  ]
}
