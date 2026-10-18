import Foundation
import SwiftUIIntelligence

/// Checks synthetic bill source, bindings, and isolated state. It does not generate a page.
public enum BillInteractionAcceptance {
  /// Uses the supplied registry. This check does not prove native interface interaction.
  @MainActor public static func validate(_ document: UIDocument, registry: CalculationRegistry) throws {
    try document.validate(registeredActions: [], registeredCalculations: registry.names)
    try ExampleAcceptance.validate(document, example: .bill)
    guard let binding = document.calculations.first,
      let fee = binding.inputs["feeMinor"], let payable = binding.outputs["payableMinor"],
      let people = binding.recordInputs["people"], let items = binding.recordInputs["items"],
      let assignments = binding.recordInputs["assignments"],
      let breakdown = binding.recordOutputs["breakdown"], let shares = binding.recordOutputs["shares"] else {
      throw UIError("The bill requires complete source and output bindings.")
    }
    func descendants(_ node: UINode) -> [UINode] { [node] + node.children.flatMap(descendants) }
    let nodes = descendants(document.root)
    func table(_ source: String, fields: Set<String>, editable: Set<String> = []) -> Bool {
      nodes.contains { $0.type == .table && $0.recordSource == source
        && Set($0.recordFields).isSuperset(of: fields) && Set($0.editableFields).isSuperset(of: editable) }
    }
    guard table(items, fields: ["name", "amountMinor"], editable: ["amountMinor"]),
      table(assignments, fields: ["itemID", "personID", "included"], editable: ["included"]),
      table(breakdown, fields: ["name", "foodMinor", "feeMinor", "totalMinor"]),
      table(shares, fields: ["name", "item", "amountMinor"]) else {
      throw UIError("The bill requires source editors and derived breakdown and share tables.")
    }
    guard document.state.contains(where: { $0.id == fee && $0.kind == .number && $0.step == 1
      && $0.minimum.isFinite && $0.maximum.isFinite
      && $0.minimum.rounded() == $0.minimum && $0.maximum.rounded() == $0.maximum
      && $0.minimum <= 151 && $0.maximum >= 153 }),
      nodes.contains(where: { $0.type == .control && $0.binding == fee
        && ($0.controlType == .stepper || $0.controlType == .slider) }) else {
      throw UIError("The bill requires a numeric fee control with integer bounds and step 1 that can reach 151 and 153.")
    }
    func containsAmount(_ text: String, amounts: Set<String>) -> Bool {
      let normalized = text.replacingOccurrences(of: ",", with: "")
      return normalized.components(separatedBy: CharacterSet.decimalDigits.inverted).contains { amounts.contains($0) }
    }
    func hasNoMajorUnits(_ label: String) -> Bool {
      let lower = label.lowercased()
      let words = Set(lower.components(separatedBy: CharacterSet.letters.inverted))
      let majorUnits: Set<String> = ["dollar", "dollars", "euro", "euros", "pound", "pounds", "yen", "yuan",
        "rupee", "rupees", "franc", "francs", "usd", "eur", "gbp", "jpy", "cny", "inr", "cad", "aud", "chf"]
      return words.isDisjoint(with: majorUnits)
        && !label.unicodeScalars.contains { $0.properties.generalCategory == .currencySymbol }
    }
    let payableMetrics = nodes.filter { $0.type == .metric && $0.valueBinding == payable }
    guard !payableMetrics.isEmpty,
      payableMetrics.allSatisfy({ $0.label.lowercased().contains("minor unit")
        && hasNoMajorUnits($0.label) && hasNoMajorUnits($0.detail)
        && !containsAmount($0.label + " " + $0.detail, amounts: ["1654", "1656", "1658"]) }) else {
      throw UIError("The bill requires an unambiguous minor-unit payable label without contradictory units or duplicated payable amounts.")
    }
    // Only reject explicit repetitions of this synthetic fixture's initial payable.
    // Other numbers and per-item statements are not interpreted as bill summaries.
    for node in nodes where node.type == .text || (node.type == .metric && node.valueBinding == nil) {
      let content = node.type == .text ? node.text
        : [node.label, node.value, node.detail].joined(separator: " ")
      let words = Set(content.lowercased().components(separatedBy: CharacterSet.letters.inverted))
      if !words.isDisjoint(with: ["payable", "total"]), containsAmount(content, amounts: ["1654"]) {
        throw UIError("The bill must not repeat a static initial payable summary.")
      }
    }
    let state = DocumentState()
    try state.load(document, calculations: registry, preservingEdits: false)
    func sourceRow(_ collection: String, name: String) throws -> RecordRow {
      guard let row = state.records[collection]?.first(where: { $0.values["name"] == .text(name) }) else {
        throw UIError("The bill omits a named source row.")
      }
      return row
    }
    let soup = try sourceRow(items, name: "Soup")
    let tea = try sourceRow(items, name: "Tea")
    let cy = try sourceRow(people, name: "Cy")
    let matrix = state.records[assignments] ?? []
    let peopleRows = state.records[people] ?? []
    let itemRows = state.records[items] ?? []
    var pairs = Set<[String]>()
    for row in matrix {
      guard case .text(let item) = row.values["itemID"], case .text(let person) = row.values["personID"],
        itemRows.contains(where: { $0.id == item }), peopleRows.contains(where: { $0.id == person }),
        pairs.insert([item, person]).inserted else { throw UIError("The bill source matrix requires unique source references.") }
    }
    guard pairs.count == peopleRows.count * itemRows.count,
      let cySoup = matrix.first(where: { $0.values["itemID"] == .text(soup.id) && $0.values["personID"] == .text(cy.id) }) else {
      throw UIError("The bill source matrix must cover each item and person.")
    }
    func number(_ value: StateValue?) throws -> Double {
      guard case .number(let value) = value, value >= 0, value.rounded() == value else {
        throw UIError("Bill outputs must use nonnegative integer minor units.")
      }
      return value
    }
    func check(soupAmount: Double, feeAmount: Double, expectedPayable: Double) throws {
      guard state.values[payable] == .number(expectedPayable),
        state.values[fee] == .number(feeAmount),
        try sourceRow(items, name: "Soup").values["amountMinor"] == .number(soupAmount),
        try sourceRow(items, name: "Tea").values["amountMinor"] == .number(502) else {
        throw UIError("The bill probe finds incorrect source values or payable minor units.")
      }
      let personal = state.records[breakdown] ?? []
      let portions = state.records[shares] ?? []
      let active = (state.records[assignments] ?? []).filter { $0.values["included"] == .boolean(true) }
      guard personal.count == 3, Set(personal.map(\.id)) == Set(peopleRows.map(\.id)), portions.count == active.count else {
        throw UIError("The bill probe finds incorrect participant or share counts.")
      }
      // Independent integer quotas for this bounded synthetic probe. Do not use the host allocator as an oracle.
      var expectedFood = Dictionary(uniqueKeysWithValues: peopleRows.map { ($0.id, 0) })
      var expectedShares: [String: Int] = [:]
      for (item, amount) in [(soup.id, Int(soupAmount)), (tea.id, 502)] {
        let included = active.filter { $0.values["itemID"] == .text(item) }.sorted {
          guard case .text(let lhs) = $0.values["personID"], case .text(let rhs) = $1.values["personID"] else { return false }
          return lhs < rhs
        }
        guard !included.isEmpty else { throw UIError("The bill item requires participants.") }
        for (rank, assignment) in included.enumerated() {
          guard case .text(let person) = assignment.values["personID"] else { throw UIError("Missing bill participant.") }
          let share = amount / included.count + (rank < amount % included.count ? 1 : 0)
          expectedShares[assignment.id] = share
          expectedFood[person, default: 0] += share
        }
      }
      let denominator = Int(soupAmount) + 502
      let feeUnits = Int(feeAmount)
      let priority = peopleRows.map(\.id).sorted {
        let lhs = feeUnits * expectedFood[$0]! % denominator
        let rhs = feeUnits * expectedFood[$1]! % denominator
        return lhs == rhs ? $0 < $1 : lhs > rhs
      }
      var expectedFees = expectedFood.mapValues { feeUnits * $0 / denominator }
      let residual = feeUnits - expectedFees.values.reduce(0, +)
      for id in priority.prefix(residual) { expectedFees[id, default: 0] += 1 }
      var seen = Set<[String]>()
      for portion in portions {
        guard case .text(let person) = portion.values["personID"], case .text(let item) = portion.values["itemID"],
          let sourcePerson = peopleRows.first(where: { $0.id == person }),
          let sourceItem = itemRows.first(where: { $0.id == item }),
          let assignment = active.first(where: { $0.values["personID"] == .text(person) && $0.values["itemID"] == .text(item) }),
          portion.id == assignment.id, portion.values["name"] == sourcePerson.values["name"],
          portion.values["item"] == sourceItem.values["name"], seen.insert([item, person]).inserted else {
          throw UIError("The bill shares must identify actual included source rows.")
        }
        guard try number(portion.values["amountMinor"]) == Double(expectedShares[portion.id]!) else {
          throw UIError("Bill item remainders must follow stable participant IDs.")
        }
      }
      for (item, amount) in [(soup.id, soupAmount), (tea.id, 502.0)] {
        let amounts = try portions.filter { $0.values["itemID"] == .text(item) }.map { try number($0.values["amountMinor"]) }
        guard amounts.reduce(0, +) == amount, let low = amounts.min(), let high = amounts.max(), high - low <= 1 else {
          throw UIError("The bill item shares must conserve each item and differ by at most one minor unit.")
        }
      }
      var foodSum = 0.0, feeSum = 0.0, totalSum = 0.0
      for person in personal {
        let food = try number(person.values["foodMinor"])
        let service = try number(person.values["feeMinor"])
        let total = try number(person.values["totalMinor"])
        let itemSum = try portions.filter { $0.values["personID"] == .text(person.id) }.reduce(0.0) { try $0 + number($1.values["amountMinor"]) }
        guard person.values["name"] == peopleRows.first(where: { $0.id == person.id })?.values["name"],
          food == itemSum, food == Double(expectedFood[person.id]!),
          service == Double(expectedFees[person.id]!), total == food + service else { throw UIError("Personal bill totals must match their underlying item shares and fee.") }
        foodSum += food; feeSum += service; totalSum += total
      }
      guard foodSum == soupAmount + 502, feeSum == feeAmount, totalSum == expectedPayable else {
        throw UIError("The bill personal totals must conserve food, fee, and payable minor units.")
      }
    }
    try check(soupAmount: 1001, feeAmount: 151, expectedPayable: 1654)
    try state.setRecord(items, row: soup.id, field: "amountMinor", to: .number(1003))
    try check(soupAmount: 1003, feeAmount: 151, expectedPayable: 1656)
    try state.set(fee, to: .number(153))
    try check(soupAmount: 1003, feeAmount: 153, expectedPayable: 1658)
    try state.setRecord(assignments, row: cySoup.id, field: "included", to: .boolean(true))
    try check(soupAmount: 1003, feeAmount: 153, expectedPayable: 1658)
    let soupAssignments = matrix.filter { $0.values["itemID"] == .text(soup.id) }
    for (index, row) in soupAssignments.enumerated() {
      if index < soupAssignments.count - 1 {
        try state.setRecord(assignments, row: row.id, field: "included", to: .boolean(false))
        try check(soupAmount: 1003, feeAmount: 153, expectedPayable: 1658)
      } else {
        let priorValues = state.values
        let priorRecords = state.records
        var rejected = false
        do { try state.setRecord(assignments, row: row.id, field: "included", to: .boolean(false)) }
        catch { rejected = true }
        guard rejected, state.values == priorValues, state.records == priorRecords else {
          throw UIError("Removing the last Soup participant must fail without changing values or records.")
        }
      }
    }
  }
}
