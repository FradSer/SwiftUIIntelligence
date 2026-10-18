import Foundation
import Testing
import SwiftUIIntelligence
import SwiftUIIntelligenceExamples
import InteractionFixtureSupport

// These synthetic fixtures test acceptance. They are not runtime page templates.
// Given remapped source IDs, the complete generic layout passes with either numeric control.
@Test @MainActor func billInteractionAcceptsRemappedGenericDocuments() throws {
  for prefix in ["alpha", "zulu"] {
    for control in ["stepper", "slider"] {
      var source = InteractionFixtures.bill(prefix: prefix, control: control)
      var root = source["root"] as! [String: Any]
      var children = root["children"] as! [[String: Any]]
      children[5]["detail"] = "Split between 3 people; exact integer amount"
      children.append(["id": "item-note", "type": "text", "text": "Per-item example: 1654 minor units"])
      root["children"] = children
      source["root"] = root
      try BillInteractionAcceptance.validate(billInteractionDocument(source), registry: ExampleCalculations.registry())
    }
  }
}

// Given correct source facts, a text-only root does not establish interaction acceptance.
@Test @MainActor func billInteractionRejectsSourceOnlyRoot() throws {
  var source = InteractionFixtures.bill()
  source["root"] = ["id": "plain", "type": "text", "text": "Bill"]
  let document = try billInteractionDocument(source)
  try ExampleAcceptance.validate(document, example: .bill)
  #expect(throws: UIError.self) {
    try BillInteractionAcceptance.validate(document, registry: ExampleCalculations.registry())
  }
}

// Given valid source data, missing reactive outputs and unrelated editors are rejected.
@Test @MainActor func billInteractionRejectsIncompleteLayout() throws {
  let mutations: [(inout [[String: Any]]) -> Void] = [
    { $0.removeLast() },
    { $0[5].removeValue(forKey: "valueBinding") },
    { $0[5]["label"] = "Payable"; $0[5]["detail"] = "Total" },
    { $0[5]["label"] = "Payable ($)"; $0[5]["detail"] = "1654 minor units" },
    { $0[5]["label"] = "Payable (minor units / dollars)" },
    { $0[5]["label"] = "Payable (minor units €)" },
    { $0[5]["detail"] = "1654 minor units" },
    { $0[5]["label"] = "Payable 1654 (minor units)" },
    { $0[5]["detail"] = "Total payable: $16.54" },
    { $0.append(["id": "stale-total", "type": "text", "text": "Total payable: 1654 minor units"]) },
    { $0.append(["id": "stale-metric", "type": "metric", "label": "Total (minor units)", "detail": "Initial bill", "value": "1654", "icon": "people"]) },
    { $0[0]["editableFields"] = [String]() },
    { $0[1]["editableFields"] = [String]() },
    { $0[2]["binding"] = "unrelated" },
    { $0[3] = ["id": "static", "type": "table", "columns": ["Total"], "rows": [["1654"]]] },
    { $0[4]["recordSource"] = "source-items"; $0[4]["recordFields"] = ["name", "amountMinor"]; $0[4]["columns"] = ["Name", "Amount"]; $0[4]["rows"] = [["Name", "Amount"]] },
  ]
  for mutate in mutations {
    var source = InteractionFixtures.bill()
    var root = source["root"] as! [String: Any]
    var children = root["children"] as! [[String: Any]]
    mutate(&children)
    root["children"] = children
    source["root"] = root
    let document = try billInteractionDocument(source)
    let registry = try ExampleCalculations.registry()
    try document.validate(registeredActions: [], registeredCalculations: registry.names)
    #expect(throws: UIError.self) { try BillInteractionAcceptance.validate(document, registry: registry) }
  }
}

// Given a complete document, the supplied registry must calculate defaults and cumulative edits.
@Test @MainActor func billInteractionRejectsIncorrectRegistry() throws {
  let good = try ExampleCalculations.registry()
  let signature = try #require(good.signatures.first { $0.id == "split-bill" })
  for failure in ["initial", "edited", "shares", "personal", "empty", "fees", "editedFees"] {
    let bad = try CalculationRegistry([.init(id: signature.id, inputs: signature.inputs, outputs: signature.outputs,
      recordInputs: signature.recordInputs, recordOutputs: signature.recordOutputs) { values, records in
        if failure == "empty" {
          var repaired = records
          repaired["assignments"] = records["assignments"]!.map { row in
            var fields = row.values
            fields["included"] = .boolean(true)
            return RecordRow(id: row.id, values: fields)
          }
          // Preserve correct behavior until an item loses its last participant.
          if let soup = records["items"]!.first(where: { $0.values["name"] == .text("Soup") }),
            !records["assignments"]!.contains(where: { $0.values["itemID"] == .text(soup.id) && $0.values["included"] == .boolean(true) }) {
            return try good.evaluate("split-bill", inputs: values, records: repaired)
          }
        }
        let result = try good.evaluate("split-bill", inputs: values, records: records)
        var outputs = result.values
        var rows = result.records
        if failure == "initial" || (failure == "edited" && values["feeMinor"] == .number(153)) {
          outputs["payableMinor"] = .number(1)
        }
        if failure == "shares" || failure == "personal" {
          let key = failure == "shares" ? "shares" : "breakdown"
          rows[key] = rows[key]!.map { row in
            var fields = row.values
            fields[failure == "shares" ? "amountMinor" : "foodMinor"] = .number(1)
            return RecordRow(id: row.id, values: fields)
          }
        }
        if failure == "fees" || (failure == "editedFees" && values["feeMinor"] == .number(153)) {
          // Conserve food, fees, and totals while violating proportional allocation.
          rows["breakdown"] = try rows["breakdown"]!.map { row in
            var fields = row.values
            let service = fields["name"] == .text("Ada") ? values["feeMinor"]! : .number(0)
            guard case .number(let food) = fields["foodMinor"], case .number(let fee) = service else {
              throw UIError("The synthetic registry requires numeric amounts.")
            }
            fields["feeMinor"] = service
            fields["totalMinor"] = .number(food + fee)
            return RecordRow(id: row.id, values: fields)
          }
        }
        return CalculationResult(values: outputs, records: rows)
      }])
    #expect(throws: UIError.self) {
      try BillInteractionAcceptance.validate(billInteractionDocument(InteractionFixtures.bill()), registry: bad)
    }
  }
}

// Given step 1, both probe fees must lie on an integer control grid and inside its bounds.
@Test @MainActor func billInteractionRequiresReachableIntegerFeeGrid() throws {
  for control in ["stepper", "slider"] {
    for (minimum, maximum, accepted) in [(150.5, 153.5, false), (0.0, 153.5, false),
      (0.0, 152.0, false), (151.0, 153.0, true), (0.0, 10000.0, true)] {
      var source = InteractionFixtures.bill(control: control)
      var declarations = source["state"] as! [[String: Any]]
      declarations[0]["minimum"] = minimum
      declarations[0]["maximum"] = maximum
      source["state"] = declarations
      let document = try billInteractionDocument(source)
      let registry = try ExampleCalculations.registry()
      try document.validate(registeredActions: [], registeredCalculations: registry.names)
      if accepted {
        try BillInteractionAcceptance.validate(document, registry: registry)
      } else {
        #expect(throws: UIError.self) { try BillInteractionAcceptance.validate(document, registry: registry) }
      }
    }
  }
}

private func billInteractionDocument(_ source: [String: Any]) throws -> UIDocument {
  try JSONDecoder().decode(UIDocument.self, from: JSONSerialization.data(withJSONObject: source))
}
