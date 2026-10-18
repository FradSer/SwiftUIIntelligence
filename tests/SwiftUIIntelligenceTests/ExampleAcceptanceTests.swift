import Foundation
import Testing
import SwiftUIIntelligence
import SwiftUIIntelligenceExamples

// Given the supplied source facts, accept remapped IDs and reject changed facts or unresolved references.
@Test func equipmentSourceRejectsUnresolvedMeasurementReferencesBeforeBindings() throws {
  for invalid in [false, true] {
    let fixture = invalid ? AcceptanceFixture.equipment.changing("metrics", row: 0, field: "productID", to: .text("invented-product-id")) : AcceptanceFixture.equipment
    let original = try fixture.document()
    var object = try #require(JSONSerialization.jsonObject(with: DocumentGenerationContract.canonicalJSON(original)) as? [String: Any])
    object["calculations"] = []
    let document = try JSONDecoder().decode(UIDocument.self, from: JSONSerialization.data(withJSONObject: object))
    if invalid {
      do {
        try ExampleAcceptance.validateSource(document, example: .equipment)
        Issue.record("Invalid product reference must fail.")
      } catch {
        #expect(error.localizedDescription.contains("invented-product-id"))
        #expect(error.localizedDescription.contains("pack-a"))
        #expect(error.localizedDescription.contains("pack-b"))
      }
    } else { try ExampleAcceptance.validateSource(document, example: .equipment) }
  }
}

@Test func equipmentAcceptancePreservesSourceFactsAndBounds() throws {
  let fixture = AcceptanceFixture.equipment
  try ExampleAcceptance.validate(fixture.document(), example: .equipment)
  // The request supplies maxima only. A lower bound must not exclude either source value.
  try ExampleAcceptance.validate(fixture.changing("limits", row: 0, field: "minimum", to: .number(-10)).document(), example: .equipment)
  for changed in [
    fixture.changing("packs", row: 0, field: "name", to: .text("Pine")),
    fixture.changing("packs", row: 0, field: "selected", to: .text("yes")),
    fixture.changing("metrics", row: 0, field: "value", to: .number(121)),
    fixture.changing("metrics", row: 1, field: "value", to: .number(901)),
    fixture.changing("metrics", row: 2, field: "value", to: .number(86)),
    fixture.changing("metrics", row: 3, field: "value", to: .number(1201)),
    fixture.changing("metrics", row: 0, field: "productID", to: .text("Cedar")),
    fixture.changing("metrics", row: 0, field: "productID", to: .text("pack-b")),
    fixture.changing("metrics", row: 0, field: "field", to: .text("cost")),
    fixture.changing("limits", row: 0, field: "maximum", to: .number(131)),
    fixture.changing("limits", row: 1, field: "maximum", to: .number(1301)),
    fixture.changing("limits", row: 0, field: "minimum", to: .number(86)),
    fixture.changing("limits", row: 1, field: "minimum", to: .number(901)),
    fixture.changing("limits", row: 1, field: "field", to: .text("price")),
    fixture.removingLast("metrics"), fixture.addingRow("packs"),
    fixture.addingRow("metrics"), fixture.addingRow("limits"),
    fixture.binding("products", to: "absent"),
  ] {
    let document = try changed.document()
    #expect(throws: UIError.self) { try ExampleAcceptance.validate(document, example: .equipment) }
  }
}

@Test func acceptanceRejectsAdditionalCalculations() throws {
  let original = try AcceptanceFixture.bill.document()
  var object = try #require(JSONSerialization.jsonObject(with: DocumentGenerationContract.canonicalJSON(original)) as? [String: Any])
  var calculations = try #require(object["calculations"] as? [[String: Any]])
  var other = calculations[0]
  other["id"] = "second"
  other["outputs"] = ["payableMinor": "otherTotal"]
  other["recordOutputs"] = ["breakdown": "otherBreakdown", "shares": "otherShares"]
  calculations.append(other)
  object["calculations"] = calculations
  var state = object["state"] as? [[String: Any]] ?? []
  state.append(["id": "otherTotal", "kind": "number", "value": 0])
  object["state"] = state
  let document = try JSONDecoder().decode(UIDocument.self, from: JSONSerialization.data(withJSONObject: object))
  #expect(throws: UIError.self) { try ExampleAcceptance.validate(document, example: .bill) }
}

@Test func billSourceFactsRejectIncompleteMatrixBeforeBindings() throws {
  let source = try AcceptanceFixture.bill.document()
  var object = try #require(JSONSerialization.jsonObject(with: DocumentGenerationContract.canonicalJSON(source)) as? [String: Any])
  object["calculations"] = []
  let valid = try JSONDecoder().decode(UIDocument.self, from: JSONSerialization.data(withJSONObject: object))
  try ExampleAcceptance.validateSource(valid, example: .bill)
  var collections = object["records"] as! [[String: Any]]
  let index = collections.firstIndex { $0["id"] as? String == "matrix" }!
  var rows = collections[index]["rows"] as! [[String: Any]]
  rows.removeLast()
  collections[index]["rows"] = rows
  object["records"] = collections
  let invalid = try JSONDecoder().decode(UIDocument.self, from: JSONSerialization.data(withJSONObject: object))
  #expect(throws: UIError.self) { try ExampleAcceptance.validateSource(invalid, example: .bill) }
}

@Test func billAcceptancePreservesAmountsAndCompleteParticipation() throws {
  let fixture = AcceptanceFixture.bill
  try ExampleAcceptance.validate(fixture.document(), example: .bill)
  var changes = [
    fixture.changing("guests", row: 0, field: "name", to: .text("Ann")),
    fixture.changing("charges", row: 0, field: "name", to: .text("Stew")),
    fixture.changing("charges", row: 0, field: "amountMinor", to: .number(1002)),
    fixture.changing("charges", row: 1, field: "amountMinor", to: .number(503)),
    fixture.changing("matrix", row: 0, field: "itemID", to: .text("Soup")),
    fixture.changing("matrix", row: 0, field: "personID", to: .text("Ada")),
    fixture.changing("matrix", row: 0, field: "personID", to: .text("guest-b")),
    fixture.removingLast("guests"), fixture.removingLast("charges"), fixture.removingLast("matrix"),
    fixture.addingRow("guests"), fixture.addingRow("charges"), fixture.addingRow("matrix"),
    fixture.binding("assignments", to: "absent"),
  ]
  for index in 0..<6 {
    changes.append(fixture.changing("matrix", row: index, field: "included", to: .boolean(![true, true, false, false, true, true][index])))
  }
  var wrongFee = fixture
  wrongFee.fee = 152
  changes.append(wrongFee)
  var missingFee = fixture
  missingFee.calculation = .init(id: "calc", capability: "split-bill", inputs: ["feeMinor": "absent"], outputs: [:], recordInputs: fixture.calculation.recordInputs)
  changes.append(missingFee)
  for changed in changes {
    let document = try changed.document()
    #expect(throws: UIError.self) { try ExampleAcceptance.validate(document, example: .bill) }
  }
}

// Given each bill input alone, check supported facts without reading fee state or changing data.
@Test func billSourceInputAcceptsSuppliedFactsWithoutFeeOrBindings() throws {
  let document = try AcceptanceFixture.bill.document()
  let encoder = JSONEncoder()
  encoder.outputFormatting = .sortedKeys
  for (input, id) in [("items", "charges"), ("people", "guests"), ("assignments", "matrix")] {
    let collection = try #require(document.records.first { $0.id == id })
    let before = try encoder.encode(collection)
    try ExampleAcceptance.validateSourceInput(capability: "split-bill", input: input, collection: collection, example: .bill)
    #expect(try encoder.encode(collection) == before)
  }
}

@Test func billSourceInputRejectsChangedFactsWithoutRepair() throws {
  let fixture = AcceptanceFixture.bill
  let encoder = JSONEncoder()
  encoder.outputFormatting = .sortedKeys
  let cases: [(String, String, AcceptanceFixture)] = [
    ("items", "charges", fixture.changing("charges", row: 0, field: "amountMinor", to: .number(1002))),
    ("items", "charges", fixture.changing("charges", row: 1, field: "amountMinor", to: .number(503))),
    ("items", "charges", fixture.changing("charges", row: 0, field: "name", to: .text("Stew"))),
    ("items", "charges", fixture.removingLast("charges")),
    ("items", "charges", fixture.addingRow("charges")),
    ("people", "guests", fixture.changing("guests", row: 0, field: "name", to: .text("Ann"))),
    ("people", "guests", fixture.changing("guests", row: 0, field: "name", to: .text("Bo"))),
    ("people", "guests", fixture.removingLast("guests")),
    ("people", "guests", fixture.addingRow("guests")),
    ("assignments", "matrix", fixture.removingLast("matrix")),
    ("assignments", "matrix", fixture.addingRow("matrix")),
  ]
  for (input, id, changed) in cases {
    let document = try changed.document()
    let collection = try #require(document.records.first { $0.id == id })
    let before = try encoder.encode(collection)
    #expect(throws: UIError.self) {
      try ExampleAcceptance.validateSourceInput(capability: "split-bill", input: input, collection: collection, example: .bill)
    }
    #expect(try encoder.encode(collection) == before)
  }
}

// Given an unsupported identity, do not infer input roles from collection IDs or schemas.
@Test func sourceInputChecksOnlySupportedCapabilityInputAndExample() throws {
  let document = try AcceptanceFixture.bill.changing("charges", row: 0, field: "amountMinor", to: .number(0)).document()
  let collection = try #require(document.records.first { $0.id == "charges" })
  for (capability, input, example) in [
    ("unknown", "items", ExampleAcceptance.Example.bill),
    ("split-bill", "unknown", .bill),
    ("split-bill", "items", .equipment),
    ("split-bill", "items", .meal),
  ] {
    try ExampleAcceptance.validateSourceInput(capability: capability, input: input, collection: collection, example: example)
  }
}

// Given six rows with wrong references, the local count check cannot replace full-source validation.
@Test func billSourceInputLeavesCrossReferencesAndFeeToFullValidation() throws {
  let changed = AcceptanceFixture.bill.changing("matrix", row: 0, field: "personID", to: .text("unknown"))
  let document = try changed.document()
  let assignments = try #require(document.records.first { $0.id == "matrix" })
  try ExampleAcceptance.validateSourceInput(capability: "split-bill", input: "assignments", collection: assignments, example: .bill)
  #expect(throws: UIError.self) { try ExampleAcceptance.validateSource(document, example: .bill) }
  #expect(throws: UIError.self) { try ExampleAcceptance.validate(document, example: .bill) }

  var wrongFee = AcceptanceFixture.bill
  wrongFee.fee = 152
  let feeDocument = try wrongFee.document()
  let items = try #require(feeDocument.records.first { $0.id == "charges" })
  try ExampleAcceptance.validateSourceInput(capability: "split-bill", input: "items", collection: items, example: .bill)
  #expect(throws: UIError.self) { try ExampleAcceptance.validateSource(feeDocument, example: .bill) }
  #expect(throws: UIError.self) { try ExampleAcceptance.validate(feeDocument, example: .bill) }
}

private struct AcceptanceFixture {
  var calculation: CalculationBinding
  var collections: [String: [RecordRow]]
  var fee = 151

  static var equipment: Self {
    .init(calculation: .init(id: "compare", capability: "compare-records", inputs: [:], outputs: [:],
      recordInputs: ["products": "packs", "measurements": "metrics", "conditions": "limits"]), collections: [
        "packs": [row("pack-a", ["name": .text("Cedar"), "selected": .boolean(true)]),
          row("pack-b", ["name": .text("Moss"), "selected": .boolean(false)])],
        "metrics": [("pack-a", "price", 120.0), ("pack-a", "weight", 900.0), ("pack-b", "price", 85.0), ("pack-b", "weight", 1200.0)].enumerated().map {
          row("metric-\($0.offset)", ["productID": .text($0.element.0), "field": .text($0.element.1), "value": .number($0.element.2)])
        },
        "limits": [row("price-limit", ["field": .text("price"), "minimum": .number(0), "maximum": .number(130)]),
          row("weight-limit", ["field": .text("weight"), "minimum": .number(0), "maximum": .number(1300)])],
      ])
  }

  static var bill: Self {
    .init(calculation: .init(id: "split", capability: "split-bill", inputs: ["feeMinor": "service"], outputs: [:],
      recordInputs: ["people": "guests", "items": "charges", "assignments": "matrix"]), collections: [
        "guests": zip(["guest-a", "guest-b", "guest-c"], ["Ada", "Bo", "Cy"]).map { row($0.0, ["name": .text($0.1)]) },
        "charges": [row("dish-s", ["name": .text("Soup"), "amountMinor": .number(1001)]),
          row("dish-t", ["name": .text("Tea"), "amountMinor": .number(502)])],
        "matrix": (0..<6).map { index in
          row("pair-\(index)", ["itemID": .text(index < 3 ? "dish-s" : "dish-t"),
            "personID": .text(["guest-a", "guest-b", "guest-c"][index % 3]),
            "included": .boolean([true, true, false, false, true, true][index])])
        },
      ])
  }

  private static func row(_ id: String, _ values: [String: StateValue]) -> RecordRow { .init(id: id, values: values) }

  func changing(_ collection: String, row index: Int, field: String, to value: StateValue) -> Self {
    var copy = self
    let row = copy.collections[collection]![index]
    var values = row.values
    values[field] = value
    copy.collections[collection]![index] = .init(id: row.id, values: values)
    return copy
  }

  func removingLast(_ collection: String) -> Self {
    var copy = self
    copy.collections[collection]!.removeLast()
    return copy
  }

  func addingRow(_ collection: String) -> Self {
    var copy = self
    copy.collections[collection]!.append(.init(id: "extra", values: collections[collection]![0].values))
    return copy
  }

  func binding(_ parameter: String, to id: String) -> Self {
    var copy = self
    var inputs = calculation.recordInputs
    inputs[parameter] = id
    copy.calculation = .init(id: calculation.id, capability: calculation.capability, inputs: calculation.inputs,
      outputs: [:], recordInputs: inputs)
    return copy
  }

  func document() throws -> UIDocument {
    struct Collection: Encodable {
      let id: String
      let schema: RecordSchema
      let rows: [RecordRow]
    }
    struct Source: Encodable {
      let version = 1
      let state: [[String: StateValue]]
      let calculations: [CalculationBinding]
      let records: [Collection]
      let root = ["id": "root", "type": "text", "text": "Source"]
    }
    let source = Source(state: [["id": .text("service"), "kind": .text("number"), "value": .number(Double(fee)), "maximum": .number(1000)]],
      calculations: [calculation], records: collections.map { id, rows in
        let fields = rows[0].values.mapValues { value -> CalculationRegistry.ValueKind in
          switch value { case .text: return .text; case .number: return .number; case .boolean: return .boolean }
        }
        return Collection(id: id, schema: .init(fields: fields), rows: rows)
      })
    // Decode without structural validation to test source acceptance independently of the core validator.
    return try JSONDecoder().decode(UIDocument.self, from: JSONEncoder().encode(source))
  }
}

@Test @MainActor func mealSourceDescriptionsReachGenerationContract() throws {
  // Given meal metadata, the source-generation contract retains the unscaled-input rules.
  let registry = try ExampleCalculations.registry()
  let signature = try #require(registry.signatures.first { $0.id == "meal-plan" })
  let ingredients = try #require(signature.recordInputDescriptions["ingredients"])
  let steps = try #require(signature.recordInputDescriptions["steps"])
  #expect(ingredients.contains("original base-recipe quantity"))
  #expect(ingredients.contains("Do not pre-scale"))
  #expect(steps.contains("original order"))
  #expect(steps.contains("Do not rescale"))
  let request = try DocumentGenerationRequest(messages: [.init(role: .user, content: "Plan a meal")],
    calculationSignatures: [signature])
  #expect(request.calculationDeclarationInstructions.contains(ingredients))
  #expect(request.calculationDeclarationInstructions.contains(steps))
}

@Test func mealSourceAcceptanceRejectsMissingBaseBeforeBinding() throws {
  let json = #"{"version":1,"state":[{"id":"count","kind":"number","value":3},{"id":"when","kind":"text","value":"2026-10-15T19:00:00Z"}],"root":{"id":"root","type":"text","text":"Source"}}"#
  let document = try UIDocument.decode(Data(json.utf8), registeredActions: [])
  #expect(throws: UIError.self) { try ExampleAcceptance.validateSource(document, example: .meal) }
}

@Test func mealAcceptanceRejectsSharedBaseAndRequestedPeople() throws {
  let json = #"{"version":1,"state":[{"id":"time","kind":"text","value":"2026-10-15T19:00:00Z"},{"id":"count","kind":"number","value":3}],"calculations":[{"id":"plan","capability":"meal-plan","inputs":{"basePeople":"count","people":"count","mealTime":"time"},"outputs":{},"recordInputs":{"ingredients":"ingredients","steps":"steps"},"recordOutputs":{"shopping":"shopping","schedule":"schedule"}}],"records":[{"id":"ingredients","schema":{"fields":{"name":"text","quantity":"number","unit":"text"}},"rows":[]},{"id":"steps","schema":{"fields":{"title":"text","minutes":"number"}},"rows":[]}],"root":{"id":"root","type":"text","text":"Plan"}}"#
  let document = try UIDocument.decode(Data(json.utf8), registeredActions: [], registeredCalculations: ["meal-plan"])
  #expect(throws: UIError.self) { try ExampleAcceptance.validate(document, example: .meal) }
}

@Test func sampleMealAcceptanceReadsBindingsRatherThanAssumingIDs() throws {
  let json = #"{"version":1,"state":[{"id":"when","kind":"text","value":"2026-10-15T19:00:00Z"},{"id":"original","kind":"number","value":2,"minimum":2,"maximum":2,"step":1},{"id":"requested","kind":"number","value":3,"minimum":1,"maximum":10000,"step":1}],"calculations":[{"id":"plan","capability":"meal-plan","inputs":{"basePeople":"original","people":"requested","mealTime":"when"},"outputs":{},"recordInputs":{"ingredients":"source","steps":"ordered"},"recordOutputs":{"shopping":"shop","schedule":"times"}}],"records":[{"id":"source","schema":{"fields":{"name":"text","quantity":"number","unit":"text"}},"rows":[{"id":"l","values":{"name":"lentils","quantity":200,"unit":"g"}},{"id":"r","values":{"name":"rice","quantity":150,"unit":"g"}},{"id":"c","values":{"name":"carrots","quantity":100,"unit":"g"}}]},{"id":"ordered","schema":{"fields":{"title":"text","minutes":"number"}},"rows":[{"id":"p","values":{"title":"preparation","minutes":10}},{"id":"c","values":{"title":"cooking","minutes":25}},{"id":"s","values":{"title":"serving","minutes":5}}]}],"root":{"id":"root","type":"text","text":"Plan"}}"#
  let document = try UIDocument.decode(Data(json.utf8), registeredActions: [], registeredCalculations: ["meal-plan"])
  try ExampleAcceptance.validate(document, example: .meal)
  // Given valid initial counts, reject declarations that permit unsupported count edits.
  // Step is control metadata, not a guarantee that StateField rejects fractional edits.
  let originalObject = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
  for id in ["original", "requested"] {
    let invalidDomains: [[String: Double]] = [
      ["minimum": -1e9, "maximum": 1e9, "step": 1],
      ["minimum": 0, "maximum": 10, "step": 1],
      ["minimum": 1, "maximum": Double(MealPlanning.maximumPeople + 1), "step": 1],
      ["minimum": 1.5, "maximum": 10, "step": 1],
      ["minimum": 1, "maximum": 10.5, "step": 1],
      ["minimum": 1, "maximum": 10, "step": 0.5],
      ["minimum": 1, "maximum": 10, "step": 2],
      [:],
    ]
    for domain in invalidDomains {
      var object = originalObject
      var state = try #require(object["state"] as? [[String: Any]])
      let index = try #require(state.firstIndex { $0["id"] as? String == id })
      for key in ["minimum", "maximum", "step"] { state[index].removeValue(forKey: key) }
      for (key, value) in domain { state[index][key] = value }
      object["state"] = state
      let invalidDomain = try UIDocument.decode(JSONSerialization.data(withJSONObject: object), registeredActions: [], registeredCalculations: ["meal-plan"])
      let before = try DocumentGenerationContract.canonicalJSON(invalidDomain)
      #expect(throws: UIError.self) { try ExampleAcceptance.validate(invalidDomain, example: .meal) }
      #expect(try DocumentGenerationContract.canonicalJSON(invalidDomain) == before)
    }
  }
  // A fixed original basis needs no editor. Valid count ranges may be narrower than the capability range.
  let narrower = try UIDocument.decode(Data(json.replacingOccurrences(of: "\"maximum\":10000", with: "\"maximum\":4").utf8), registeredActions: [], registeredCalculations: ["meal-plan"])
  try ExampleAcceptance.validate(narrower, example: .meal)
  let requestedField = try #require(document.state.first { $0.id == "requested" })
  try requestedField.validate(.number(3.5))
  // Given original recipe facts without bindings, early validation must accept them.
  var sourceObject = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
  sourceObject.removeValue(forKey: "calculations")
  let sourceData = try JSONSerialization.data(withJSONObject: sourceObject)
  let sourceJSON = try #require(String(data: sourceData, encoding: .utf8))
  let source = try UIDocument.decode(sourceData, registeredActions: [])
  try ExampleAcceptance.validateSource(source, example: .meal)
  for collection in source.records {
    let input = collection.id == "source" ? "ingredients" : "steps"
    try ExampleAcceptance.validateSourceInput(capability: "meal-plan", input: input, collection: collection, example: .meal)
  }
  // When source quantities are pre-scaled, or step facts change, reject before binding.
  let changedSources = [
    sourceJSON.replacingOccurrences(of: "\"quantity\":200", with: "\"quantity\":300")
      .replacingOccurrences(of: "\"quantity\":150", with: "\"quantity\":225")
      .replacingOccurrences(of: "\"quantity\":100", with: "\"quantity\":150"),
    sourceJSON.replacingOccurrences(of: "\"minutes\":10", with: "\"minutes\":15"),
    sourceJSON.replacingOccurrences(of: "preparation", with: "pending")
      .replacingOccurrences(of: "cooking", with: "preparation")
      .replacingOccurrences(of: "pending", with: "cooking")
      .replacingOccurrences(of: "\"minutes\":10", with: "\"minutes\":-1")
      .replacingOccurrences(of: "\"minutes\":25", with: "\"minutes\":10")
      .replacingOccurrences(of: "\"minutes\":-1", with: "\"minutes\":25"),
  ]
  for changedSource in changedSources {
    let invalidSource = try UIDocument.decode(Data(changedSource.utf8), registeredActions: [])
    #expect(throws: UIError.self) { try ExampleAcceptance.validateSource(invalidSource, example: .meal) }
    let input = changedSource == changedSources[0] ? "ingredients" : "steps"
    let id = input == "ingredients" ? "source" : "ordered"
    let collection = try #require(invalidSource.records.first { $0.id == id })
    #expect(throws: UIError.self) {
      try ExampleAcceptance.validateSourceInput(capability: "meal-plan", input: input, collection: collection, example: .meal)
    }
    // Unrelated identities remain outside this example validator's scope.
    try ExampleAcceptance.validateSourceInput(capability: "other", input: input, collection: collection, example: .meal)
    try ExampleAcceptance.validateSourceInput(capability: "meal-plan", input: "other", collection: collection, example: .meal)
    try ExampleAcceptance.validateSourceInput(capability: "meal-plan", input: input, collection: collection, example: .bill)
  }
  let equivalent = try UIDocument.decode(Data(json.replacingOccurrences(of: "2026-10-15T19:00:00Z", with: "2026-10-15T19:00:00+00:00").utf8), registeredActions: [], registeredCalculations: ["meal-plan"])
  try ExampleAcceptance.validate(equivalent, example: .meal)
  let changed = json.replacingOccurrences(of: "\"quantity\":200", with: "\"quantity\":201")
  let invalid = try UIDocument.decode(Data(changed.utf8), registeredActions: [], registeredCalculations: ["meal-plan"])
  #expect(throws: UIError.self) { try ExampleAcceptance.validate(invalid, example: .meal) }
}
