import Foundation
import SwiftUIIntelligence

/// Example hosts register these pure capabilities. The core SDK has no domain rules.
@MainActor public enum ExampleCalculations {
  public static func registry() throws -> CalculationRegistry {
    try CalculationRegistry([mealCapability, billCapability, comparisonCapability])
  }

  private static var mealCapability: CalculationRegistry.Capability {
    .init(id: "meal-plan", inputs: ["basePeople": .number, "people": .number, "mealTime": .instant], outputs: [:],
      recordInputs: [
        "ingredients": .init(fields: ["name": .text, "quantity": .number, "unit": .text]),
        "steps": .init(fields: ["title": .text, "minutes": .number]),
      ], recordOutputs: [
        "shopping": .init(fields: ["name": .text, "quantity": .number, "unit": .text]),
        "schedule": .init(fields: ["title": .text, "start": .text, "end": .text]),
      ], recordInputDescriptions: [
        "ingredients": "One row per supplied ingredient, with the original base-recipe quantity and unit for basePeople. Do not pre-scale quantities for the requested people; the calculation scales them.",
        "steps": "One row per supplied recipe step in its original order, with the original duration in minutes. Do not rescale durations for the requested people.",
      ], inputNumberConstraints: [
        "basePeople": .init(minimum: 1, maximum: Double(MealPlanning.maximumPeople), integer: true, step: 1),
        "people": .init(minimum: 1, maximum: Double(MealPlanning.maximumPeople), integer: true, step: 1),
      ]) { values, records in
        let basePeople = try integer(values["basePeople"], name: "basePeople")
        let people = try integer(values["people"], name: "people")
        let mealText = try text(values["mealTime"])
        let formatter = ISO8601DateFormatter()
        guard let mealTime = formatter.date(from: mealText) else { throw UIError("Meal time must be an ISO8601 instant.") }
        let ingredients = try records["ingredients"]!.map { row in
          MealPlanning.Ingredient(id: row.id, name: try text(row.values["name"]),
            quantity: try number(row.values["quantity"]), unit: try text(row.values["unit"]))
        }
        let steps = try records["steps"]!.map { row in
          MealPlanning.Step(id: row.id, title: try text(row.values["title"]),
            durationMinutes: try integer(row.values["minutes"], name: "minutes"))
        }
        let plan = try MealPlanning.plan(.init(basePeople: basePeople, people: people,
          ingredients: ingredients, steps: steps, mealTime: mealTime))
        let shopping = plan.ingredients.map { ingredient in
          RecordRow(id: ingredient.id, values: ["name": .text(ingredient.name), "quantity": .number(ingredient.quantity),
            "unit": .text(ingredient.unit)])
        }
        let schedule = plan.steps.map { step in
          RecordRow(id: step.id, values: ["title": .text(step.title),
            "start": .text(formatter.string(from: step.start)), "end": .text(formatter.string(from: step.end))])
        }
        return CalculationResult(values: [:], records: ["shopping": shopping, "schedule": schedule])
      }
  }

  private static var comparisonCapability: CalculationRegistry.Capability {
    .init(id: "compare-records", inputs: [:], outputs: [:], recordInputs: [
      "products": .init(fields: ["name": .text, "selected": .boolean]),
      "measurements": .init(fields: ["productID": .text, "field": .text, "value": .number]),
      "conditions": .init(fields: ["field": .text, "minimum": .number, "maximum": .number]),
    ], recordOutputs: [
      "matches": .init(fields: ["name": .text, "selected": .boolean]),
      "measurements": .init(fields: ["productID": .text, "name": .text, "field": .text, "value": .number]),
    ], recordReferences: [.init(input: "measurements", field: "productID", targetInput: "products")], recordInputDescriptions: [
      "products": "One row per supplied product, with its exact name and selection flag. Do not create rows for measurement fields.",
      "measurements": "One row per supplied product and numeric field. productID references the actual products row ID; value is the supplied measurement.",
      "conditions": "One row per numeric filter field, not per product. minimum and maximum are editable filter bounds, not individual product measurements. Include all supplied candidates initially.",
    ]) { _, records in
      let products = records["products"]!
      let measurements = records["measurements"]!
      let ids = Set(products.map(\.id))
      var fields = [String: [String: Double]]()
      for measurement in measurements {
        let product = try text(measurement.values["productID"])
        let field = try text(measurement.values["field"])
        guard ids.contains(product), fields[product]?[field] == nil else { throw UIError("Invalid or duplicate product measurement.") }
        fields[product, default: [:]][field] = try number(measurement.values["value"])
      }
      var selected = Set<String>()
      let inputs = try products.map { product in
        guard case .boolean(let isSelected) = product.values["selected"] else { throw UIError("Invalid product selection.") }
        if isSelected { selected.insert(product.id) }
        return EquipmentComparison.Record(id: product.id, name: try text(product.values["name"]), fields: fields[product.id] ?? [:])
      }
      let constraints = try records["conditions"]!.map { row in
        EquipmentComparison.Constraint(field: try text(row.values["field"]), minimum: try number(row.values["minimum"]), maximum: try number(row.values["maximum"]))
      }
      let result = try EquipmentComparison.compare(.init(records: inputs, constraints: constraints, selectedIDs: selected))
      let matches = result.records.map { product in
        RecordRow(id: product.id, values: ["name": .text(product.name), "selected": .boolean(result.selectedIDs.contains(product.id))])
      }
      let names = Dictionary(uniqueKeysWithValues: result.records.map { ($0.id, $0.name) })
      let points = try measurements.filter { row in names[try text(row.values["productID"])] != nil }.map { row in
        RecordRow(id: row.id, values: ["productID": .text(try text(row.values["productID"])), "name": .text(names[try text(row.values["productID"])]!),
          "field": .text(try text(row.values["field"])), "value": .number(try number(row.values["value"]))])
      }
      return CalculationResult(values: [:], records: ["matches": matches, "measurements": points])
    }
  }

  private static var billCapability: CalculationRegistry.Capability {
    .init(id: "split-bill", inputs: ["feeMinor": .number], outputs: ["payableMinor": .number],
      recordInputs: [
        "people": .init(fields: ["name": .text]),
        "items": .init(fields: ["name": .text, "amountMinor": .number]),
        "assignments": .init(fields: ["itemID": .text, "personID": .text, "included": .boolean]),
      ], recordOutputs: [
        "breakdown": .init(fields: ["name": .text, "foodMinor": .number, "feeMinor": .number, "totalMinor": .number]),
        "shares": .init(fields: ["personID": .text, "name": .text, "itemID": .text, "item": .text, "amountMinor": .number]),
      ], recordReferences: [
        .init(input: "assignments", field: "itemID", targetInput: "items"),
        .init(input: "assignments", field: "personID", targetInput: "people"),
      ], recordInputDescriptions: [
        "people": "One row per named participant. Food items and service fees are not people.",
        "items": "One row per supplied food or drink charge. The separately supplied service fee is a scalar input, not an item row.",
        "assignments": "One row for every combination of item and person. Group by item: for each item, author an assignment row for each participant in order, setting included to true if they share, or false if excluded. Every (itemID, personID) pair must appear exactly once.",
      ], inputNumberConstraints: [
        "feeMinor": .init(minimum: 0, maximum: 1_000_000, integer: true, step: 1),
      ]) { values, records in
        let people = records["people"]!
        let items = records["items"]!
        let assignments = records["assignments"]!
        let peopleIDs = Set(people.map(\.id))
        let itemIDs = Set(items.map(\.id))
        var pairs = Set<[String]>()
        var assignmentIDs = [[String]: String]()
        var participants = [String: [String]]()
        for assignment in assignments {
          let item = try text(assignment.values["itemID"])
          let person = try text(assignment.values["personID"])
          guard itemIDs.contains(item), peopleIDs.contains(person), pairs.insert([item, person]).inserted,
            case .boolean(let included) = assignment.values["included"] else { throw UIError("Invalid bill participation assignment.") }
          assignmentIDs[[item, person]] = assignment.id
          if included { participants[item, default: []].append(person) }
        }
        let inputItems = try items.map { row in
          BillAllocation.Item(id: row.id, amount: try minorUnits(row.values["amountMinor"]), participantIDs: participants[row.id] ?? [])
        }
        let bill = try BillAllocation.allocate(.init(personIDs: people.map(\.id), items: inputItems,
          fee: try minorUnits(values["feeMinor"])))
        guard bill.payable <= 1_000_000_000 else { throw UIError("Bill total exceeds the record numeric limit.") }
        let names = Dictionary(uniqueKeysWithValues: try people.map { ($0.id, try text($0.values["name"])) })
        let breakdown = bill.people.map { person in
          RecordRow(id: person.id, values: ["name": .text(names[person.id]!), "foodMinor": .number(Double(person.food)),
            "feeMinor": .number(Double(person.fee)), "totalMinor": .number(Double(person.total))])
        }
        let itemNames = Dictionary(uniqueKeysWithValues: try items.map { ($0.id, try text($0.values["name"])) })
        let shares = bill.people.flatMap { person in
          person.itemShares.map { share in
            RecordRow(id: assignmentIDs[[share.itemID, person.id]]!, values: ["personID": .text(person.id), "name": .text(names[person.id]!),
              "itemID": .text(share.itemID), "item": .text(itemNames[share.itemID]!), "amountMinor": .number(Double(share.amount))])
          }
        }
        return CalculationResult(values: ["payableMinor": .number(Double(bill.payable))], records: ["breakdown": breakdown, "shares": shares])
      }
  }

  private static func minorUnits(_ value: StateValue?) throws -> Int64 {
    let number = try number(value)
    guard number >= 0, let result = Int64(exactly: number) else { throw UIError("Money requires nonnegative integer minor units.") }
    return result
  }

  private static func integer(_ value: StateValue?, name: String) throws -> Int {
    let number = try number(value)
    guard let result = Int(exactly: number) else { throw UIError("\(name) must be an integer.") }
    return result
  }
  private static func number(_ value: StateValue?) throws -> Double {
    guard case .number(let result) = value else { throw UIError("A numeric calculation input is required.") }
    return result
  }
  private static func text(_ value: StateValue?) throws -> String {
    guard case .text(let result) = value else { throw UIError("A text calculation input is required.") }
    return result
  }
}
