import Foundation

// Example-owned calculation shared by runnable hosts and regression tests.
public enum MealPlanning {
  /// Both people counts use the inclusive range 1...10000.
  public static let maximumPeople = 10_000

  public struct Input: Equatable, Sendable {
    public let basePeople: Int
    public let people: Int
    public let ingredients: [Ingredient]
    /// The caller supplies the execution order. Steps do not run concurrently.
    public let steps: [Step]
    public let mealTime: Date

    public init(basePeople: Int, people: Int, ingredients: [Ingredient], steps: [Step], mealTime: Date) {
      self.basePeople = basePeople
      self.people = people
      self.ingredients = ingredients
      self.steps = steps
      self.mealTime = mealTime
    }
  }

  public struct Ingredient: Equatable, Sendable {
    public let id: String
    public let name: String
    public let quantity: Double
    public let unit: String

    public init(id: String, name: String, quantity: Double, unit: String) {
      self.id = id
      self.name = name
      self.quantity = quantity
      self.unit = unit
    }
  }

  public struct Step: Equatable, Sendable {
    public let id: String
    public let title: String
    public let durationMinutes: Int

    public init(id: String, title: String, durationMinutes: Int) {
      self.id = id
      self.title = title
      self.durationMinutes = durationMinutes
    }
  }

  public struct ScheduledStep: Equatable, Sendable {
    public let id: String
    public let title: String
    public let start: Date
    public let end: Date

    public init(id: String, title: String, start: Date, end: Date) {
      self.id = id
      self.title = title
      self.start = start
      self.end = end
    }
  }

  public struct Result: Equatable, Sendable {
    public let scaleFactor: Double
    public let ingredients: [Ingredient]
    public let steps: [ScheduledStep]

    public init(scaleFactor: Double, ingredients: [Ingredient], steps: [ScheduledStep]) {
      self.scaleFactor = scaleFactor
      self.ingredients = ingredients
      self.steps = steps
    }
  }

  public enum PlanningError: Error, Equatable, Sendable {
    case invalidBasePeople
    case invalidPeople
    case duplicateIngredientID(String)
    case duplicateStepID(String)
    case invalidQuantity(String)
    case negativeDuration(String)
    case invalidMealTime
    case overflow
  }

  /// Scales original quantities and schedules ordered steps backward from the supplied instant.
  public static func plan(_ input: Input) throws -> Result {
    guard (1...maximumPeople).contains(input.basePeople) else { throw PlanningError.invalidBasePeople }
    guard (1...maximumPeople).contains(input.people) else { throw PlanningError.invalidPeople }
    guard input.mealTime.timeIntervalSinceReferenceDate.isFinite else { throw PlanningError.invalidMealTime }
    let factor = Double(input.people) / Double(input.basePeople)
    var ingredientIDs = Set<String>()
    let ingredients = try input.ingredients.map { ingredient in
      guard ingredientIDs.insert(ingredient.id).inserted else {
        throw PlanningError.duplicateIngredientID(ingredient.id)
      }
      guard ingredient.quantity.isFinite, ingredient.quantity >= 0 else {
        throw PlanningError.invalidQuantity(ingredient.id)
      }
      let quantity = ingredient.quantity * factor
      guard quantity.isFinite else { throw PlanningError.overflow }
      return Ingredient(id: ingredient.id, name: ingredient.name, quantity: quantity, unit: ingredient.unit)
    }
    var stepIDs = Set<String>()
    var totalSeconds = 0
    let durations = try input.steps.map { step in
      guard stepIDs.insert(step.id).inserted else { throw PlanningError.duplicateStepID(step.id) }
      guard step.durationMinutes >= 0 else { throw PlanningError.negativeDuration(step.id) }
      let (seconds, productOverflow) = step.durationMinutes.multipliedReportingOverflow(by: 60)
      let (total, sumOverflow) = totalSeconds.addingReportingOverflow(seconds)
      guard !productOverflow, !sumOverflow, Double(exactly: seconds) != nil, Double(exactly: total) != nil else {
        throw PlanningError.overflow
      }
      totalSeconds = total
      return seconds
    }
    var end = input.mealTime
    var scheduled: [ScheduledStep] = []
    for (step, seconds) in zip(input.steps, durations).reversed() {
      let duration = Double(seconds)
      let start = end.addingTimeInterval(-duration)
      // Reject dates whose precision cannot represent the supplied duration.
      guard start.timeIntervalSinceReferenceDate.isFinite,
        end.timeIntervalSince(start) == duration else { throw PlanningError.overflow }
      scheduled.append(.init(id: step.id, title: step.title, start: start, end: end))
      end = start
    }
    return Result(scaleFactor: factor, ingredients: ingredients, steps: scheduled.reversed())
  }
}
