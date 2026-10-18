import Foundation
import SwiftUIIntelligence

/// Checks synthetic source facts only. This validator neither generates nor repairs documents.
public enum ExampleAcceptance {
  public enum Example: Sendable { case equipment, bill, meal }

  /// Partial checks for one synthetic source input, identified by capability and input name.
  /// Bill items and people check supplied facts; assignments check only the row count.
  /// Meal ingredients and steps check original quantities, order, and durations.
  /// Other identities are not checked. Cross-references, fees, and other example facts
  /// still require full-source and final binding-aware validation. This method does not repair data.
  public static func validateSourceInput(capability: String, input: String, collection: RecordCollection, example: Example) throws {
    if example == .meal, capability == "meal-plan" {
      switch input {
      case "ingredients": try validateMealIngredients(collection.rows)
      case "steps": try validateMealSteps(collection.rows)
      default: break
      }
      return
    }
    guard example == .bill, capability == "split-bill" else { return }
    let rows = collection.rows
    switch input {
    case "items":
      guard rows.count == 2,
        [("Soup", 1001.0), ("Tea", 502.0)].allSatisfy({ name, amount in
          rows.contains { $0.values["name"] == .text(name) && $0.values["amountMinor"] == .number(amount) }
        }) else {
        throw UIError("Bill source items require exactly Soup 1001 and Tea 502 in integer minor units.")
      }
    case "people":
      guard rows.count == 3,
        ["Ada", "Bo", "Cy"].allSatisfy({ name in rows.contains { $0.values["name"] == .text(name) } }) else {
        throw UIError("Bill source people require exactly Ada, Bo, and Cy.")
      }
    case "assignments":
      guard rows.count == 6 else {
        throw UIError("Bill source assignments require six rows; full-source validation must check participation and references.")
      }
    default: return
    }
  }

  /// Early source-only check. Final binding-aware validation remains required.
  public static func validateSource(_ document: UIDocument, example: Example) throws {
    if example == .equipment {
      func source(_ fields: Set<String>) throws -> [RecordRow] {
        let matches = document.records.filter { Set($0.schema.fields.keys) == fields }
        guard matches.count == 1 else { throw UIError("Comparison source requires one collection for each registered schema.") }
        return matches[0].rows
      }
      try validateEquipmentRows(products: source(["name", "selected"]),
        measurements: source(["productID", "field", "value"]),
        conditions: source(["field", "minimum", "maximum"]))
      return
    }
    if example == .bill {
      func source(_ fields: Set<String>) throws -> [RecordRow] {
        let matches = document.records.filter { Set($0.schema.fields.keys) == fields }
        guard matches.count == 1 else { throw UIError("Bill source requires one collection for each declared schema.") }
        return matches[0].rows
      }
      let people = try source(["name"])
      let items = try source(["name", "amountMinor"])
      let assignments = try source(["itemID", "personID", "included"])
      guard people.count == 3, items.count == 2, assignments.count == 6,
        document.state.contains(where: { $0.value == .number(151) }),
        ["Ada", "Bo", "Cy"].allSatisfy({ name in people.contains { $0.values["name"] == .text(name) } }) else {
        throw UIError("Bill source requires Ada, Bo, Cy, two items, all six participation pairs, and fee 151 minor units.")
      }
      for (name, amount, included) in [("Soup", 1001.0, ["Ada", "Bo"]), ("Tea", 502.0, ["Bo", "Cy"])] {
        guard let item = items.first(where: { $0.values["name"] == .text(name) }), item.values["amountMinor"] == .number(amount) else {
          throw UIError("Bill source changes a supplied item or integer minor-unit amount.")
        }
        for person in people {
          let expected = included.contains(where: { person.values["name"] == .text($0) })
          guard assignments.contains(where: { $0.values["itemID"] == .text(item.id) && $0.values["personID"] == .text(person.id) && $0.values["included"] == .boolean(expected) }) else {
            throw UIError("Bill source participation must reference actual item and person row IDs, including excluded pairs.")
          }
        }
      }
      return
    }
    guard example == .meal else { return }
    func source(_ fields: Set<String>) throws -> [RecordRow] {
      let matches = document.records.filter { Set($0.schema.fields.keys) == fields }
      guard matches.count == 1 else { throw UIError("Meal source requires one collection for each declared schema.") }
      return matches[0].rows
    }
    let numbers = document.state.compactMap { field -> Double? in
      if case .number(let number) = field.value { return number }
      return nil
    }
    guard numbers.contains(2), numbers.contains(3) else {
      throw UIError("Meal source requires distinct numeric values for base people 2 and requested people 3.")
    }
    guard document.state.contains(where: { field in
      guard case .text(let value) = field.value else { return false }
      return ISO8601DateFormatter().date(from: value) == ISO8601DateFormatter().date(from: "2026-10-15T19:00:00Z")
    }) else { throw UIError("Meal source requires the ISO8601 meal instant 2026-10-15T19:00:00Z in a text or date state field.") }
    try validateMealIngredients(source(["name", "quantity", "unit"]))
    try validateMealSteps(source(["title", "minutes"]))
  }

  public static func validate(_ document: UIDocument, example: Example) throws {
    guard document.calculations.count == 1 else { throw UIError("The source example requires exactly one calculation.") }
    let calculation = document.calculations[0]
    guard Set(calculation.inputs.values).isDisjoint(with: calculation.outputs.values) else {
      throw UIError("A calculated output cannot replace a supplied source input.")
    }
    switch example {
    case .equipment: try validateEquipment(document)
    case .bill: try validateBill(document)
    case .meal: try validateMeal(document)
    }
  }

  private static func binding(_ capability: String, in document: UIDocument) throws -> CalculationBinding {
    guard let binding = document.calculations.first(where: { $0.capability == capability }) else {
      throw UIError("The generated document omits its calculation capability.")
    }
    return binding
  }

  private static func rows(_ parameter: String, binding: CalculationBinding, in document: UIDocument) throws -> [RecordRow] {
    guard let id = binding.recordInputs[parameter], let collection = document.records.first(where: { $0.id == id }) else {
      throw UIError("The generated document omits a supplied source collection.")
    }
    return collection.rows
  }

  private static func validateEquipment(_ document: UIDocument) throws {
    let binding = try binding("compare-records", in: document)
    let products = try rows("products", binding: binding, in: document)
    let measurements = try rows("measurements", binding: binding, in: document)
    let conditions = try rows("conditions", binding: binding, in: document)
    try validateEquipmentRows(products: products, measurements: measurements, conditions: conditions)
  }

  private static func validateEquipmentRows(products: [RecordRow], measurements: [RecordRow], conditions: [RecordRow]) throws {
    guard products.count == 2, measurements.count == 4, conditions.count == 2 else {
      throw UIError("The generated comparison changes the supplied source counts.")
    }
    let productIDs = Set(products.map(\.id))
    for measurement in measurements {
      guard case .text(let reference) = measurement.values["productID"] else {
        throw UIError("A measurement requires its authored product row ID.")
      }
      guard productIDs.contains(reference) else {
        throw UIError("Measurement '\(measurement.id)' references unknown productID '\(reference)'. Available authored product IDs: \(productIDs.sorted().joined(separator: ", ")). Preserve source facts and author valid references.")
      }
    }
    let expected: [(String, Double, Double)] = [("Cedar", 120, 900), ("Moss", 85, 1200)]
    for (name, price, weight) in expected {
      guard let product = products.first(where: { $0.values["name"] == .text(name) }),
        case .boolean = product.values["selected"] else {
        throw UIError("The generated comparison changes a supplied product or omits its selection value.")
      }
      for (field, value) in [("price", price), ("weight", weight)] {
        guard measurements.contains(where: {
          $0.values["productID"] == .text(product.id) && $0.values["field"] == .text(field) && $0.values["value"] == .number(value)
        }) else { throw UIError("The generated comparison changes a supplied measurement or product reference.") }
      }
    }
    // The request supplies maxima only. Lower bounds must include both supplied products.
    for (field, lowest, maximum) in [("price", 85.0, 130.0), ("weight", 900.0, 1300.0)] {
      guard let condition = conditions.first(where: { $0.values["field"] == .text(field) }),
        case .number(let minimum) = condition.values["minimum"], minimum <= lowest,
        condition.values["maximum"] == .number(maximum) else {
        throw UIError("The generated comparison changes a requested maximum or excludes a supplied measurement.")
      }
    }
  }

  private static func validateBill(_ document: UIDocument) throws {
    let binding = try binding("split-bill", in: document)
    guard let fee = binding.inputs["feeMinor"], document.state.contains(where: {
      $0.id == fee && $0.value == .number(151)
    }) else { throw UIError("The generated bill changes the supplied service fee.") }
    let people = try rows("people", binding: binding, in: document)
    let items = try rows("items", binding: binding, in: document)
    let assignments = try rows("assignments", binding: binding, in: document)
    guard people.count == 3, items.count == 2, assignments.count == 6,
      ["Ada", "Bo", "Cy"].allSatisfy({ name in people.contains(where: { $0.values["name"] == .text(name) }) }) else {
      throw UIError("The generated bill changes the supplied participants or source counts.")
    }
    for (name, amount, included) in [("Soup", 1001.0, ["Ada", "Bo"]), ("Tea", 502.0, ["Bo", "Cy"])] {
      guard let item = items.first(where: { $0.values["name"] == .text(name) }), item.values["amountMinor"] == .number(amount) else {
        throw UIError("The generated bill changes a supplied item or amount.")
      }
      for person in people {
        let participates = included.contains(where: { person.values["name"] == .text($0) })
        guard assignments.contains(where: {
          $0.values["itemID"] == .text(item.id) && $0.values["personID"] == .text(person.id)
            && $0.values["included"] == .boolean(participates)
        }) else { throw UIError("The generated bill changes a supplied participation value or reference.") }
      }
    }
  }

  private static func validateMeal(_ document: UIDocument) throws {
    guard let binding = document.calculations.first(where: { $0.capability == "meal-plan" }) else {
      throw UIError("The generated meal omits its calculation capability.")
    }
    let fields = Dictionary(uniqueKeysWithValues: document.state.map { ($0.id, $0.value) })
    guard let base = binding.inputs["basePeople"], fields[base] == .number(2) else {
      throw UIError("basePeople must reference the authored number state with value 2.")
    }
    guard let people = binding.inputs["people"], fields[people] == .number(3) else {
      throw UIError("people must reference the authored number state with value 3.")
    }
    // Check the bound declarations, not unrelated fields with the same initial values.
    // Integer endpoints and unit steps describe a supported control range. StateField
    // does not enforce a step lattice for arbitrary programmatic numeric edits.
    for id in [base, people] {
      guard let field = document.state.first(where: { $0.id == id }), field.kind == .number,
        field.minimum.isFinite, field.maximum.isFinite,
        field.minimum >= 1, field.maximum <= Double(MealPlanning.maximumPeople),
        field.minimum <= field.maximum,
        field.minimum.rounded() == field.minimum, field.maximum.rounded() == field.maximum,
        field.step == 1 else {
        throw UIError("Meal people counts require integer bounds within 1...\(MealPlanning.maximumPeople) and step 1.")
      }
    }
    guard let time = binding.inputs["mealTime"], case .text(let instant) = fields[time],
      ISO8601DateFormatter().date(from: instant) == ISO8601DateFormatter().date(from: "2026-10-15T19:00:00Z") else {
      throw UIError("mealTime must reference the authored ISO8601 state with instant 2026-10-15T19:00:00Z, not a signature description.")
    }
    try validateMealIngredients(rows("ingredients", binding: binding, in: document))
    try validateMealSteps(rows("steps", binding: binding, in: document))
  }

  private static func validateMealIngredients(_ ingredients: [RecordRow]) throws {
    let expected: [(String, Double)] = [("lentils", 200), ("rice", 150), ("carrots", 100)]
    guard ingredients.count == expected.count else { throw UIError("The generated meal changes the ingredient count.") }
    for (name, amount) in expected {
      guard ingredients.contains(where: { $0.values["name"] == .text(name) && $0.values["quantity"] == .number(amount) && $0.values["unit"] == .text("g") }) else {
        throw UIError("The generated meal changes a supplied ingredient.")
      }
    }
  }

  private static func validateMealSteps(_ steps: [RecordRow]) throws {
    let ordered: [(String, Double)] = [("preparation", 10), ("cooking", 25), ("serving", 5)]
    guard steps.count == ordered.count, zip(steps, ordered).allSatisfy({ row, expected in
      row.values["title"] == .text(expected.0) && row.values["minutes"] == .number(expected.1)
    }) else { throw UIError("The generated meal changes supplied step order or duration.") }
  }
}
