import Foundation
import SwiftUIIntelligence

/// Checks synthetic equipment bindings and isolated edits. It does not generate a page.
public enum EquipmentInteractionAcceptance {
  /// Uses the supplied registry. Native interface interaction requires a separate check.
  @MainActor public static func validate(_ document: UIDocument, registry: CalculationRegistry) throws {
    try document.validate(registeredActions: [], registeredCalculations: registry.names)
    try ExampleAcceptance.validate(document, example: .equipment)
    guard let binding = document.calculations.first,
      let products = binding.recordInputs["products"],
      let measurements = binding.recordInputs["measurements"],
      let conditions = binding.recordInputs["conditions"],
      let matches = binding.recordOutputs["matches"],
      let points = binding.recordOutputs["measurements"] else {
      throw UIError("Equipment requires complete source and output bindings.")
    }
    func descendants(_ node: UINode) -> [UINode] { [node] + node.children.flatMap(descendants) }
    let nodes = descendants(document.root)
    func table(_ source: String, fields: Set<String>, editable: Set<String> = []) -> Bool {
      nodes.contains { $0.type == .table && $0.recordSource == source
        && Set($0.recordFields).isSuperset(of: fields) && Set($0.editableFields).isSuperset(of: editable) }
    }
    guard table(products, fields: ["name", "selected"], editable: ["selected"]),
      table(conditions, fields: ["field", "minimum", "maximum"], editable: ["minimum", "maximum"]),
      table(matches, fields: ["name", "selected"]),
      table(points, fields: ["name", "field", "value"]) else {
      throw UIError("Equipment requires product selectors, bound editors, and derived match and measurement tables.")
    }
    let charts = nodes.filter { $0.type == .chart && $0.recordSource == points
      && ($0.recordFields == ["name", "value", "field"] || $0.recordFields == ["field", "value", "name"]) }
    guard !charts.isEmpty else {
      throw UIError("Equipment requires a derived measurement chart with product names, values, and field names.")
    }
    // Keep each unit within its measurement phrase and bound presentation label.
    // Tokens elsewhere on the page cannot repair missing or swapped units.
    let unitTokens: Set<String> = ["usd", "g", "gram", "grams"]
    var labeledFields = Set<String>()
    for node in nodes where [measurements, conditions, points].contains(node.recordSource) {
      for label in [node.text, node.title, node.label, node.detail] + node.columns {
        let phrases = label.lowercased().replacingOccurrences(of: " and ", with: "/")
          .components(separatedBy: CharacterSet(charactersIn: "/,;"))
        for phrase in phrases {
          let tokens = Set(phrase.split(whereSeparator: { !$0.isLetter }).map(String.init))
          let measurements = tokens.intersection(["price", "weight"])
          let units = tokens.intersection(unitTokens)
          // An ordinary heading need not repeat units supplied by a measurement label.
          if units.isEmpty { continue }
          for field in measurements {
            let allowed: Set<String> = field == "price" ? ["usd"] : ["g", "gram", "grams"]
            guard units.isSubset(of: allowed) else {
              throw UIError("Equipment must label price in USD and weight in grams (g).")
            }
            labeledFields.insert(field)
          }
        }
      }
    }
    guard labeledFields == ["price", "weight"] else {
      throw UIError("Equipment must label price in USD and weight in grams (g).")
    }
    let state = DocumentState()
    try state.load(document, calculations: registry, preservingEdits: false)
    let sourceProducts = state.records[products] ?? []
    let sourceMeasurements = state.records[measurements] ?? []
    func condition(_ field: String) throws -> RecordRow {
      guard let row = state.records[conditions]?.first(where: { $0.values["field"] == .text(field) }) else {
        throw UIError("Equipment omits a required condition row.")
      }
      return row
    }
    let price = try condition("price")
    let weight = try condition("weight")
    func check(names: Set<String>) throws {
      let expectedProducts = (state.records[products] ?? []).filter { row in
        names.contains { row.values["name"] == .text($0) }
      }
      let ids = Set(expectedProducts.map(\.id))
      let expectedMatches = expectedProducts.map { row in
        RecordRow(id: row.id, values: ["name": row.values["name"]!,
          "selected": row.values["selected"]!])
      }
      let expectedPoints = try sourceMeasurements.filter { row in
        guard case .text(let id) = row.values["productID"] else { throw UIError("Invalid equipment measurement reference.") }
        return ids.contains(id)
      }.map { row in
        guard let product = expectedProducts.first(where: { row.values["productID"] == .text($0.id) }) else {
          throw UIError("Invalid equipment product reference.")
        }
        return RecordRow(id: row.id, values: ["productID": .text(product.id), "name": product.values["name"]!,
          "field": row.values["field"]!, "value": row.values["value"]!])
      }
      let expected = [matches: expectedMatches, points: expectedPoints]
      for (source, rows) in expected {
        guard let actual = state.records[source], actual.count == rows.count,
          Set(actual.map(\.id)) == Set(rows.map(\.id)),
          rows.allSatisfy({ row in actual.first(where: { $0.id == row.id }) == row }) else {
          throw UIError("Equipment results must preserve current source identities, values, and selection.")
        }
      }
      // Source records and chart projections each have a 32-row SDK cap. This fixture needs at most four points.
      guard expectedPoints.count <= 32 else { throw UIError("Equipment exceeds the chart record cap.") }
      for node in nodes where node.type == .table && (node.recordSource == matches || node.recordSource == points) {
        let actual = try node.resolvedRows(in: state.records)
        let wanted = try node.resolvedRows(in: expected)
        guard actual.count == wanted.count, Set(actual) == Set(wanted) else {
          throw UIError("Equipment table projections must reflect current derived records, including empty results.")
        }
      }
      for chart in charts {
        let actual = try chart.resolvedPoints(values: state.values, records: state.records)
        let wanted = try chart.resolvedPoints(values: state.values, records: expected)
        guard actual.count == wanted.count, actual.allSatisfy({ point in
          wanted.contains { $0.label == point.label && $0.series == point.series && $0.value == point.value }
        }) else { throw UIError("Equipment charts must reflect current measurements, including empty results.") }
      }
    }
    try check(names: ["Cedar", "Moss"])
    for name in ["Cedar", "Moss"] {
      guard let row = sourceProducts.first(where: { $0.values["name"] == .text(name) }) else {
        throw UIError("Equipment omits a named source product.")
      }
      for selected in [true, false, true] {
        try state.setRecord(products, row: row.id, field: "selected", to: .boolean(selected))
        try check(names: ["Cedar", "Moss"])
      }
    }
    try state.setRecord(conditions, row: price.id, field: "maximum", to: .number(100))
    try check(names: ["Moss"])
    try state.setRecord(conditions, row: weight.id, field: "maximum", to: .number(1000))
    try check(names: [])
    try state.setRecord(conditions, row: price.id, field: "maximum", to: .number(130))
    try check(names: ["Cedar"])
    try state.setRecord(conditions, row: weight.id, field: "maximum", to: .number(1300))
    try check(names: ["Cedar", "Moss"])
    try state.setRecord(conditions, row: price.id, field: "minimum", to: .number(100))
    try check(names: ["Cedar"])
    try state.setRecord(conditions, row: price.id, field: "minimum", to: price.values["minimum"]!)
    try check(names: ["Cedar", "Moss"])
    try state.setRecord(conditions, row: weight.id, field: "minimum", to: .number(1000))
    try check(names: ["Moss"])
    try state.setRecord(conditions, row: weight.id, field: "minimum", to: weight.values["minimum"]!)
    try check(names: ["Cedar", "Moss"])
  }
}
