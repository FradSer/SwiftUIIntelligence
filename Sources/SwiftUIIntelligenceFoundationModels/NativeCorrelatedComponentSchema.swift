import Foundation
import SwiftUIIntelligence

/// Correlates projection references with declared schemas. The model still selects the collection and fields.
enum NativeCorrelatedComponentSchema {
  static func correlate(componentSchema: Data, declarationsData: Data,
    selectedSignatures: [CalculationRegistry.Signature], kind: UINode.Kind, projected: Bool,
    purpose: String? = nil) throws -> Data {
    guard projected else { return componentSchema }
    guard [.list, .table, .chart, .timeline].contains(kind) else {
      throw UIError("Record correlation requires a projected list, table, chart, or timeline.")
    }
    let declarations = try JSONDecoder().decode(Declarations.self, from: declarationsData)
    var inputRoles = [String: String]()
    for binding in declarations.calculations {
      for (parameter, id) in binding.recordInputs {
        inputRoles[id] = parameter
      }
    }
    var collections = declarations.records.map { Collection(id: $0.id, schema: $0.schema, editable: true, role: inputRoles[$0.id]) }
    for binding in declarations.calculations {
      guard let signature = selectedSignatures.first(where: { $0.id == binding.capability }) else {
        throw UIError("Record correlation requires the selected calculation signature.")
      }
      for (parameter, id) in binding.recordOutputs {
        guard let schema = signature.recordOutputs[parameter] else {
          throw UIError("Record correlation references an unknown output parameter.")
        }
        collections.append(Collection(id: id, schema: schema, editable: false, role: parameter))
      }
    }
    for collection in collections { try collection.schema.validate([]) }
    let prefersEditable: Bool = {
      guard let purpose else { return false }
      let lower = purpose.lowercased()
      return lower.contains("edit") || lower.contains("condition") || lower.contains("select") || lower.contains("input") || lower.contains("toggle") || lower.contains("choice") || lower.contains("assign") || lower.contains("matrix") || lower.contains("participat")
    }()
    func matchScore(_ collection: Collection) -> Int {
      guard let purpose = purpose?.lowercased() else { return 0 }
      var score = 0
      if let role = collection.role?.lowercased() {
        if purpose.contains(role) { score += 100 }
        if role == "items" && (purpose.contains("item") || purpose.contains("amount") || purpose.contains("food") || purpose.contains("dish")) { score += 100 }
        if role == "assignments" && (purpose.contains("assign") || purpose.contains("participat") || purpose.contains("toggle") || purpose.contains("exclud") || purpose.contains("includ")) { score += 100 }
        if role == "shares" && (purpose.contains("share") || purpose.contains("split")) { score += 100 }
        if role == "breakdown" && (purpose.contains("breakdown") || purpose.contains("personal") || purpose.contains("total") || purpose.contains("fee")) { score += 100 }
        if role == "shopping" && (purpose.contains("shop") || purpose.contains("ingredient")) { score += 50 }
        if role == "schedule" && (purpose.contains("schedul") || purpose.contains("time") || purpose.contains("step")) { score += 50 }
        if role == "matches" && (purpose.contains("match") || purpose.contains("result") || purpose.contains("filter")) { score += 50 }
        if role == "measurements" && (purpose.contains("measur") || purpose.contains("point") || purpose.contains("chart")) { score += 50 }
        if role == "conditions" && (purpose.contains("condit") || purpose.contains("bound") || purpose.contains("limit")) { score += 50 }
        if role == "products" && (purpose.contains("product") || purpose.contains("select")) { score += 50 }
      }
      return score
    }
    let eligible = collections.filter { collection in
      switch kind {
      case .list, .timeline: return collection.schema.fields.values.contains(.text)
      case .chart:
        let textCount = collection.schema.fields.values.filter { $0 == .text }.count
        let numberCount = collection.schema.fields.values.filter { $0 == .number }.count
        return textCount >= 1 && numberCount >= 1 && (textCount >= 2 || numberCount == 1)
      default: return true
      }
    }.sorted { lhs, rhs in
      let scoreL = matchScore(lhs)
      let scoreR = matchScore(rhs)
      if scoreL != scoreR {
        return scoreL > scoreR
      }
      if lhs.editable != rhs.editable {
        if prefersEditable {
          return lhs.editable && !rhs.editable
        } else {
          return !lhs.editable && rhs.editable
        }
      }
      return lhs.id < rhs.id
    }
    guard !eligible.isEmpty else { throw UIError("No declared collection supports this record projection.") }
    guard var root = try JSONSerialization.jsonObject(with: componentSchema) as? [String: Any],
      root["$ref"] as? String == "#/$defs/\(kind.rawValue)",
      var definitions = root["$defs"] as? [String: [String: Any]],
      let definition = definitions[kind.rawValue] else {
      throw UIError("Record correlation requires an extracted component schema.")
    }
    let branches = try leaves(definition)
    definitions[kind.rawValue] = ["anyOf": try branches.flatMap { branch in
      try eligible.map { try correlate(branch, collection: $0, kind: kind, prefersEditable: prefersEditable) }
    }]
    root["$defs"] = definitions
    // Reuse extraction to retain the complete existing reference closure, including static fallback grammar.
    return try NativeComponentLayout.componentSchema(
      from: JSONSerialization.data(withJSONObject: root, options: [.sortedKeys]), kind: kind, projected: true)
  }

  private struct Declarations: Decodable {
    let records: [RecordCollection]
    let calculations: [CalculationBinding]

    private enum CodingKeys: String, CodingKey { case records, calculations }

    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      records = try container.decodeIfPresent([RecordCollection].self, forKey: .records) ?? []
      calculations = try container.decode([CalculationBinding].self, forKey: .calculations)
    }
  }

  private struct Collection {
    let id: String
    let schema: RecordSchema
    let editable: Bool
    let role: String?
  }

  private static func leaves(_ definition: [String: Any]) throws -> [[String: Any]] {
    guard let branches = definition["anyOf"] as? [[String: Any]] else { return [definition] }
    guard !branches.isEmpty else { throw UIError("Record correlation requires component branches.") }
    return try branches.flatMap { try leaves($0) }
  }

  private static func correlate(_ branch: [String: Any], collection: Collection,
    kind: UINode.Kind, prefersEditable: Bool = false) throws -> [String: Any] {
    guard var fields = branch["properties"] as? [String: [String: Any]],
      fields["type"]?["enum"] as? [String] == [kind.rawValue],
      var source = fields["recordSource"], var projection = fields["recordFields"],
      var items = projection["items"] as? [String: Any] else {
      throw UIError("Record correlation requires the requested kind and projection properties.")
    }
    let textOnly = kind == .list || kind == .timeline
    let names = collection.schema.fields.filter { !textOnly || $0.value == .text }.keys.sorted()
    source["enum"] = [collection.id]
    if let role = collection.role {
      source["description"] = "Record collection ID for \(role). Select '\(collection.id)' for \(role)."
    }
    fields["recordSource"] = source
    // Charts keep the canonical three positions. The document validator checks text/number/text order.
    // The native schema converter does not support prefixItems, so its item enum contains all declared fields.
    items["enum"] = names
    projection["items"] = items
    if kind == .chart {
      let textNames = collection.schema.fields.filter { $0.value == .text }.keys.sorted()
      let numberNames = collection.schema.fields.filter { $0.value == .number }.keys.sorted()
      let labelEx = textNames.contains("name") ? "'name'" : "'\(textNames.first ?? "label")'"
      let valEx = numberNames.contains("value") ? "'value'" : "'\(numberNames.first ?? "value")'"
      let seriesEx = textNames.contains("field") ? "'field'" : "'\(textNames.last ?? "series")'"
      projection["description"] = "Exact three record fields in canonical order: first the text label field \(labelEx), second the numeric value field \(valEx), third the text series field \(seriesEx). Must be in exact [\(labelEx), \(valEx), \(seriesEx)] order."
    } else if kind == .timeline {
      projection["description"] = "Exact three record fields in canonical order: first the start time field, second the title field, third the end/detail field (e.g. ['start', 'title', 'end']). Must be in exact ['start', 'title', 'end'] order."
    } else if kind == .table {
      let maxCols = min(names.count, 6)
      if var columns = fields["columns"] {
        columns["maxItems"] = maxCols
        columns["description"] = "Header title for each column. Must contain exactly one column title per field in recordFields (columns.count == recordFields.count)."
        fields["columns"] = columns
      }
      if var rows = fields["rows"], var item = rows["items"] as? [String: Any] {
        item["maxItems"] = maxCols
        rows["items"] = item
        fields["rows"] = rows
      }
      projection["maxItems"] = maxCols
      if collection.role == "measurements" {
        projection["description"] = "Fields to display. For measurements table, select ['name', 'field', 'value']."
      } else {
        projection["description"] = "The record fields to display, exactly one field per column header in columns (recordFields.count == columns.count)."
      }
    }
    fields["recordFields"] = projection
    var required = Set(branch["required"] as? [String] ?? [])
    required.formUnion(["recordSource", "recordFields"])
    if collection.editable, kind == .table, var editable = fields["editableFields"],
      var editableItems = editable["items"] as? [String: Any] {
      editableItems["enum"] = collection.schema.fields.keys.sorted()
      editable["items"] = editableItems
      fields["editableFields"] = editable
      if prefersEditable {
        required.insert("editableFields")
      }
    } else {
      fields.removeValue(forKey: "editableFields")
      required.remove("editableFields")
    }
    var result = branch
    result["properties"] = fields
    result["required"] = required.sorted()
    return result
  }
}
