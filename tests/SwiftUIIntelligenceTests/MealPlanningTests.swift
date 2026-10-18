import Foundation
import Testing
import SwiftUIIntelligenceExamples

private let mealDate = ISO8601DateFormatter().date(from: "2026-10-15T19:00:00Z")!
private let mealIngredients: [MealPlanning.Ingredient] = [
  .init(id: "rice", name: "Rice", quantity: 120, unit: "g"),
  .init(id: "water", name: "Water", quantity: 0.25, unit: "L"),
]
private let mealSteps: [MealPlanning.Step] = [
  .init(id: "z-prep", title: "Prepare", durationMinutes: 10),
  .init(id: "a-cook", title: "Cook", durationMinutes: 20),
  .init(id: "serve", title: "Serve", durationMinutes: 0),
]

// Given base quantities for two, changing people scales from the original quantities each time.
@Test func mealScalesFromTwoToThreeToFive() throws {
  for (people, factor) in [(2, 1.0), (3, 1.5), (5, 2.5)] {
    let result = try MealPlanning.plan(.init(basePeople: 2, people: people,
      ingredients: mealIngredients, steps: mealSteps, mealTime: mealDate))
    #expect(result.scaleFactor == factor)
    #expect(result.ingredients == [
      .init(id: "rice", name: "Rice", quantity: 120 * factor, unit: "g"),
      .init(id: "water", name: "Water", quantity: 0.25 * factor, unit: "L"),
    ])
    #expect(result.steps.map(\.id) == mealSteps.map(\.id))
  }
}

// Given ordered steps, changing the meal instant shifts every boundary by the same seconds.
@Test func mealTimeShiftsEveryStepWithoutCalendarRules() throws {
  let first = try MealPlanning.plan(.init(basePeople: 2, people: 3,
    ingredients: mealIngredients, steps: mealSteps, mealTime: mealDate))
  #expect(first.steps.map(\.title) == mealSteps.map(\.title))
  #expect(first.steps.map(\.start) == [-1800.0, -1200, 0].map { mealDate.addingTimeInterval($0) })
  #expect(first.steps.map(\.end) == [-1200.0, 0, 0].map { mealDate.addingTimeInterval($0) })
  for shift in [-90061.0, 3661.0] {
    let shifted = try MealPlanning.plan(.init(basePeople: 2, people: 3,
      ingredients: mealIngredients, steps: mealSteps, mealTime: mealDate.addingTimeInterval(shift)))
    #expect(shifted.ingredients == first.ingredients)
    #expect(shifted.steps.map(\.start) == first.steps.map { $0.start.addingTimeInterval(shift) })
    #expect(shifted.steps.map(\.end) == first.steps.map { $0.end.addingTimeInterval(shift) })
  }
}

// Given unseen ingredients and people counts, the result retains supplied names, units, and IDs.
@Test func mealAcceptsUnseenIngredientsAndPeople() throws {
  let ingredients: [MealPlanning.Ingredient] = [
    .init(id: "new-7", name: "Teff", quantity: 3.5, unit: "scoops"),
    .init(id: "new-9", name: "Sumac", quantity: 0, unit: "pinches"),
  ]
  for people in [1, 7, 13, MealPlanning.maximumPeople] {
    let result = try MealPlanning.plan(.init(basePeople: 7, people: people,
      ingredients: ingredients, steps: [], mealTime: mealDate))
    #expect(result.ingredients.map(\.id) == ingredients.map(\.id))
    #expect(result.ingredients.map(\.name) == ingredients.map(\.name))
    #expect(result.ingredients.map(\.unit) == ingredients.map(\.unit))
    #expect(result.ingredients.map(\.quantity) == [3.5 * (Double(people) / 7), 0])
    #expect(result.steps.isEmpty)
  }
}

// Given invalid inputs, validation throws instead of returning partial output.
@Test func mealRejectsInvalidInputsAndOverflow() {
  typealias Input = MealPlanning.Input
  typealias Failure = MealPlanning.PlanningError
  let ingredient = mealIngredients[0]
  let step = mealSteps[0]
  let cases: [(Input, Failure)] = [
    (.init(basePeople: 0, people: 1, ingredients: [], steps: [], mealTime: mealDate), .invalidBasePeople),
    (.init(basePeople: MealPlanning.maximumPeople + 1, people: 1, ingredients: [], steps: [], mealTime: mealDate), .invalidBasePeople),
    (.init(basePeople: 1, people: 0, ingredients: [], steps: [], mealTime: mealDate), .invalidPeople),
    (.init(basePeople: 1, people: -1, ingredients: [], steps: [], mealTime: mealDate), .invalidPeople),
    (.init(basePeople: 1, people: MealPlanning.maximumPeople + 1, ingredients: [], steps: [], mealTime: mealDate), .invalidPeople),
    (.init(basePeople: 1, people: 1, ingredients: [ingredient, ingredient], steps: [], mealTime: mealDate), .duplicateIngredientID("rice")),
    (.init(basePeople: 1, people: 1, ingredients: [], steps: [step, step], mealTime: mealDate), .duplicateStepID("z-prep")),
    (.init(basePeople: 1, people: 1, ingredients: [], steps: [.init(id: "x", title: "X", durationMinutes: -1)], mealTime: mealDate), .negativeDuration("x")),
    (.init(basePeople: 1, people: 1, ingredients: [], steps: [.init(id: "x", title: "X", durationMinutes: Int.max)], mealTime: mealDate), .overflow),
    (.init(basePeople: 1, people: 1, ingredients: [], steps: [
      .init(id: "x", title: "X", durationMinutes: Int.max / 60),
      .init(id: "y", title: "Y", durationMinutes: Int.max / 60),
    ], mealTime: mealDate), .overflow),
    (.init(basePeople: 1, people: 1, ingredients: [], steps: [], mealTime: Date(timeIntervalSinceReferenceDate: .infinity)), .invalidMealTime),
    (.init(basePeople: 1, people: 1, ingredients: [], steps: [step], mealTime: Date(timeIntervalSinceReferenceDate: -Double.greatestFiniteMagnitude)), .overflow),
  ]
  // Each duration must convert exactly, even when the cumulative total is representable.
  let impreciseDuration = MealPlanning.Input(basePeople: 1, people: 1, ingredients: [], steps: [
    .init(id: "short", title: "Short", durationMinutes: 1),
    .init(id: "long", title: "Long", durationMinutes: 600479950316067),
  ], mealTime: Date(timeIntervalSinceReferenceDate: Double(36028797018964020)))
  #expect(throws: Failure.overflow) { try MealPlanning.plan(impreciseDuration) }
  for (input, error) in cases {
    #expect(throws: error) { try MealPlanning.plan(input) }
  }
  for quantity in [-1.0, Double.nan, .infinity, -.infinity] {
    #expect(throws: Failure.invalidQuantity("x")) {
      try MealPlanning.plan(.init(basePeople: 1, people: 1,
        ingredients: [.init(id: "x", name: "X", quantity: quantity, unit: "g")], steps: [], mealTime: mealDate))
    }
  }
  #expect(throws: Failure.overflow) {
    try MealPlanning.plan(.init(basePeople: 1, people: 2,
      ingredients: [.init(id: "x", name: "X", quantity: .greatestFiniteMagnitude, unit: "g")],
      steps: [], mealTime: mealDate))
  }
}

// Given empty collections and positive people counts, both output collections are empty.
@Test func mealAllowsEmptyCollections() throws {
  let result = try MealPlanning.plan(.init(basePeople: 2, people: 5,
    ingredients: [], steps: [], mealTime: mealDate))
  #expect(result.scaleFactor == 2.5)
  #expect(result.ingredients.isEmpty)
  #expect(result.steps.isEmpty)
}
