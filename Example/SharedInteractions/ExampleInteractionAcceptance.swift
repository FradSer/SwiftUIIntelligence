import Foundation
import SwiftUIIntelligence

/// Checks the initial meal contract. This check does not generate or repair documents.
public enum ExampleInteractionAcceptance {
  /// Checks structure and runs mutations on fresh state, not on a rendered interface or the host's state.
  @MainActor public static func validateMeal(_ document: UIDocument, registry: CalculationRegistry) throws {
    try document.validate(registeredActions: [], registeredCalculations: registry.names)
    try ExampleAcceptance.validate(document, example: .meal)
    guard let binding = document.calculations.first,
      let people = binding.inputs["people"], let base = binding.inputs["basePeople"],
      let mealTime = binding.inputs["mealTime"], let shopping = binding.recordOutputs["shopping"],
      let schedule = binding.recordOutputs["schedule"] else {
      throw UIError("The meal requires complete input and output bindings.")
    }
    let nodes = descendants(document.root)
    guard let peopleField = document.state.first(where: { $0.id == people }), peopleField.step == 1,
      peopleField.minimum.rounded() == peopleField.minimum,
      peopleField.maximum.rounded() == peopleField.maximum else {
      throw UIError("The people control must support one-person changes with step 1 and integer bounds.")
    }
    guard nodes.contains(where: {
      $0.type == .control && $0.binding == people && ($0.controlType == .stepper || $0.controlType == .slider)
    }) else { throw UIError("The meal requires a numeric control bound to people.") }
    guard nodes.contains(where: {
      $0.type == .control && $0.binding == mealTime && $0.controlType == .datePicker
    }) else { throw UIError("The meal requires a date picker bound to mealTime.") }
    guard !nodes.contains(where: { $0.type == .control && $0.binding == base }) else {
      throw UIError("The meal must not expose a control for basePeople.")
    }
    guard nodes.contains(where: {
      $0.type == .table && $0.recordSource == shopping && Set($0.recordFields).isSuperset(of: ["name", "quantity", "unit"])
    }) else { throw UIError("The meal requires a derived shopping table with name, quantity, and unit.") }
    guard nodes.contains(where: {
      $0.type == .timeline && $0.recordSource == schedule && $0.recordFields == ["start", "title", "end"]
    }) else { throw UIError("The meal requires a derived timeline with fields ordered start, title, end.") }

    // This isolated state probe checks the supplied registry. It does not prove renderer interaction.
    let state = DocumentState()
    try state.load(document, calculations: registry, preservingEdits: false)
    let formatter = ISO8601DateFormatter()
    guard let instant = formatter.date(from: "2026-10-15T19:00:00Z") else {
      throw UIError("The meal acceptance instant is invalid.")
    }
    func check(quantities: [Double], shift: TimeInterval) throws {
      guard state.values[base] == .number(2) else { throw UIError("The meal changes basePeople during the state probe.") }
      try checkShopping(state.records[shopping] ?? [], quantities: quantities)
      try checkSchedule(state.records[schedule] ?? [], instant: instant.addingTimeInterval(shift))
    }
    try check(quantities: [300, 225, 150], shift: 0)
    try state.set(people, to: .number(4))
    try check(quantities: [400, 300, 200], shift: 0)
    try state.set(mealTime, to: .text(formatter.string(from: instant.addingTimeInterval(3600))))
    try check(quantities: [400, 300, 200], shift: 3600)
    try state.set(people, to: .number(3))
    try check(quantities: [300, 225, 150], shift: 3600)
  }

  private static func descendants(_ node: UINode) -> [UINode] {
    [node] + node.children.flatMap { descendants($0) }
  }

  private static func checkShopping(_ rows: [RecordRow], quantities: [Double]) throws {
    let names = ["lentils", "rice", "carrots"]
    guard rows.count == names.count else { throw UIError("The meal state probe requires three shopping rows.") }
    for (name, quantity) in zip(names, quantities) {
      guard rows.filter({ $0.values["name"] == .text(name) && $0.values["quantity"] == .number(quantity)
        && $0.values["unit"] == .text("g") }).count == 1 else {
        throw UIError("The meal state probe finds an incorrect shopping quantity, name, or unit.")
      }
    }
  }

  private static func checkSchedule(_ rows: [RecordRow], instant: Date) throws {
    let titles = ["preparation", "cooking", "serving"]
    let starts: [TimeInterval] = [-2400, -1800, -300]
    let ends: [TimeInterval] = [-1800, -300, 0]
    guard rows.count == titles.count else { throw UIError("The meal state probe requires three ordered schedule rows.") }
    let formatter = ISO8601DateFormatter()
    for (index, row) in rows.enumerated() {
      guard row.values["title"] == .text(titles[index]),
        case .text(let start) = row.values["start"], case .text(let end) = row.values["end"],
        formatter.date(from: start) == instant.addingTimeInterval(starts[index]),
        formatter.date(from: end) == instant.addingTimeInterval(ends[index]) else {
        throw UIError("The meal state probe finds an incorrect schedule order, start, or end.")
      }
    }
  }
}
