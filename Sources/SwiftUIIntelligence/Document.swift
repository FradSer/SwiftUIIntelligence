import Foundation

public struct UIError: LocalizedError, Sendable {
  public let message: String
  public var errorDescription: String? { message }
  public init(_ message: String) { self.message = message }
}

private struct JSONKey: CodingKey {
  let stringValue: String
  var intValue: Int? { nil }
  init?(stringValue: String) { self.stringValue = stringValue }
  init?(intValue: Int) { return nil }
}

func checkKeys(_ decoder: any Decoder, allowed: Set<String>) throws {
  let keys = try decoder.container(keyedBy: JSONKey.self).allKeys.map(\.stringValue)
  if let unknown = keys.sorted().first(where: { !allowed.contains($0) }) {
    throw UIError("Unknown field '\(unknown)' at \(location(decoder.codingPath)).")
  }
}

private func location(_ path: [any CodingKey]) -> String {
  path.isEmpty ? "$" : "$." + path.map(\.stringValue).joined(separator: ".")
}

public enum CardColor: String, Codable, CaseIterable, Sendable {
  case neutral, blue, orange, green, purple
}

/// Immutable nodes can only be created by the constrained decoder.
public struct UINode: Codable, Identifiable, Sendable {
  public enum Kind: String, Codable, Sendable, CaseIterable {
    case vstack, hstack, grid, text, button, section, list, table, callout, metric, iconList, badge, progress, chart, form, control, navigationLink, timeline
  }
  public enum TextStyle: String, Codable, Sendable { case title, headline, body, caption }
  public let cardColor: CardColor?
  public let id: String
  public let type: Kind
  public let children: [UINode]
  public let spacing: Double
  public let columnCount: Int
  public let text: String
  public let style: TextStyle
  public let title: String
  public let action: String
  public enum Tone: String, Codable, Sendable { case note, success, warning }
  public let items: [String]
  public let columns: [String]
  public let rows: [[String]]
  public let tone: Tone
  public let icon: String?
  public let label: String
  public let value: String
  public let valueBinding: String?
  public let detail: String
  public let iconItems: [IconItem]
  public let completed: Double
  public let total: Double
  public enum ChartStyle: String, Codable, Sendable { case line, area, bar, donut, radar }
  public let chartStyle: ChartStyle
  public let points: [ChartPoint]

  public enum ControlType: String, Codable, Sendable, CaseIterable { case textField, textEditor, toggle, picker, slider, stepper, datePicker }
  public let controlType: ControlType
  public let binding: String
  public let destination: String
  public let events: [TimelineEvent]
  public let recordSource: String?
  public let recordFields: [String]
  public let editableFields: [String]

  private enum CodingKeys: String, CodingKey {
    case editableFields, recordSource, recordFields, cardColor, id, type, children, spacing, columnCount, text, style, title, action, items, columns, rows, tone, icon, label, value, valueBinding, detail, iconItems, completed, total, chartStyle, points, controlType, binding, destination, events
  }

  public init(from decoder: any Decoder) throws {
    // Stop before recursively decoding another node, including malformed deep trees.
    guard decoder.codingPath.count <= 26 else { throw UIError("UI nesting exceeds 12 levels.") }
    let values = try decoder.container(keyedBy: CodingKeys.self)
    id = try values.decode(String.self, forKey: .id)
    let rawType = try values.decode(String.self, forKey: .type)
    guard let kind = Kind(rawValue: rawType) else {
      throw UIError(
        "Unknown component '\(rawType)' at \(location(decoder.codingPath)). Allowed: \(Kind.allCases.map(\.rawValue).joined(separator: ", "))."
      )
    }
    type = kind
    editableFields = values.contains(.editableFields) ? try values.decode([String].self, forKey: .editableFields) : []
    recordSource = values.contains(.recordSource) ? try values.decode(String.self, forKey: .recordSource) : nil
    recordFields = values.contains(.recordFields) ? try values.decode([String].self, forKey: .recordFields) : []
    cardColor = values.contains(.cardColor) ? try values.decode(CardColor.self, forKey: .cardColor) : nil
    items = kind == .list ? try values.decode([String].self, forKey: .items) : []
    columns = kind == .table ? try values.decode([String].self, forKey: .columns) : []
    rows = kind == .table ? try values.decode([[String]].self, forKey: .rows) : []
    tone = (kind == .callout || kind == .badge) ? try values.decode(Tone.self, forKey: .tone) : .note
    columnCount = kind == .grid ? try values.decode(Int.self, forKey: .columnCount) : 1
    icon = try values.decodeIfPresent(String.self, forKey: .icon)
    label = kind == .metric ? try values.decode(String.self, forKey: .label) : ""
    value = kind == .metric ? try values.decode(String.self, forKey: .value) : ""
    valueBinding = values.contains(.valueBinding) ? try values.decode(String.self, forKey: .valueBinding) : nil
    detail = kind == .metric ? try values.decode(String.self, forKey: .detail) : ""
    iconItems = kind == .iconList ? try values.decode([IconItem].self, forKey: .iconItems) : []
    completed = kind == .progress ? try values.decode(Double.self, forKey: .completed) : 0
    total = kind == .progress ? try values.decode(Double.self, forKey: .total) : 1
    chartStyle = kind == .chart ? try values.decode(ChartStyle.self, forKey: .chartStyle) : .line
    points = kind == .chart ? try values.decode([ChartPoint].self, forKey: .points) : []
    controlType = kind == .control ? try values.decode(ControlType.self, forKey: .controlType) : .textField
    binding = kind == .control ? try values.decode(String.self, forKey: .binding)
      : kind == .text && values.contains(.binding) ? try values.decode(String.self, forKey: .binding) : ""
    destination = kind == .navigationLink ? try values.decode(String.self, forKey: .destination) : ""
    events = kind == .timeline ? try values.decode([TimelineEvent].self, forKey: .events) : []
    switch kind {
    case .vstack, .hstack, .grid, .section, .form:
      try checkKeys(
        decoder,
        allowed: kind == .grid ? ["cardColor", "id", "type", "children", "spacing", "columnCount"] : (kind == .section || kind == .form)
          ? ["cardColor", "id", "type", "children", "title", "spacing", "icon"] : ["cardColor", "id", "type", "children", "spacing"])
      children = try values.decode([UINode].self, forKey: .children)
      spacing = values.contains(.spacing) ? try values.decode(Double.self, forKey: .spacing) : 16
      text = ""
      style = .body
      title = (kind == .section || kind == .form) ? try values.decode(String.self, forKey: .title) : ""
      action = ""
    case .text, .callout, .badge:
      try checkKeys(
        decoder,
        allowed: kind == .text
          ? ["cardColor", "id", "type", "text", "style", "icon", "binding"] : ["cardColor", "id", "type", "text", "tone", "icon"])
      text = try values.decode(String.self, forKey: .text)
      style = values.contains(.style) ? try values.decode(TextStyle.self, forKey: .style) : .body
      children = []
      spacing = 0
      title = ""
      action = ""
    case .list, .table:
      try checkKeys(
        decoder,
        allowed: kind == .list ? ["cardColor", "id", "type", "items", "recordSource", "recordFields"] : ["cardColor", "id", "type", "columns", "rows", "recordSource", "recordFields", "editableFields"])
      children = []
      spacing = 0
      text = ""
      style = .body
      title = ""
      action = ""
    case .button:
      try checkKeys(decoder, allowed: ["cardColor", "id", "type", "title", "action", "icon"])
      title = try values.decode(String.self, forKey: .title)
      action = try values.decode(String.self, forKey: .action)
      children = []
      spacing = 0
      text = ""
      style = .body
    case .control, .navigationLink, .timeline:
      let fields: Set<String> = kind == .control ? ["cardColor", "id", "type", "title", "controlType", "binding"] : kind == .navigationLink ? ["cardColor", "id", "type", "title", "destination"] : ["cardColor", "id", "type", "title", "events", "recordSource", "recordFields"]
      try checkKeys(decoder, allowed: fields)
      title = try values.decode(String.self, forKey: .title)
      children = []; spacing = 0; text = ""; style = .body; action = ""
    case .metric, .iconList, .progress, .chart:
      let fields: Set<String> = switch kind {
      case .metric: ["cardColor", "id", "type", "label", "value", "valueBinding", "detail", "icon"]
      case .iconList: ["cardColor", "id", "type", "iconItems"]
      case .progress: ["cardColor", "id", "type", "title", "completed", "total", "icon"]
      default: ["cardColor", "id", "type", "title", "chartStyle", "points", "recordSource", "recordFields"]
      }
      try checkKeys(decoder, allowed: fields)
      if kind == .metric || kind == .progress {
        guard icon != nil else { throw UIError("Missing icon for \(kind.rawValue).") }
      }
      title = (kind == .chart || kind == .progress) ? try values.decode(String.self, forKey: .title) : ""
      children = []; spacing = 0; text = ""; style = .body; action = ""
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encodeIfPresent(cardColor, forKey: .cardColor)
    try c.encodeIfPresent(recordSource, forKey: .recordSource)
    if !recordFields.isEmpty { try c.encode(recordFields, forKey: .recordFields) }
    if !editableFields.isEmpty { try c.encode(editableFields, forKey: .editableFields) }
    try c.encode(id, forKey: .id)
    try c.encode(type, forKey: .type)
    try c.encodeIfPresent(icon, forKey: .icon)
    switch type {
    case .vstack, .hstack, .grid, .section, .form:
      if type == .grid { try c.encode(columnCount, forKey: .columnCount) }
      if type == .section || type == .form { try c.encode(title, forKey: .title) }
      try c.encode(children, forKey: .children)
      try c.encode(spacing, forKey: .spacing)
    case .text:
      if !binding.isEmpty { try c.encode(binding, forKey: .binding) }
      try c.encode(text, forKey: .text)
      try c.encode(style, forKey: .style)
    case .callout, .badge:
      try c.encode(text, forKey: .text)
      try c.encode(tone, forKey: .tone)
    case .list:
      try c.encode(items, forKey: .items)
    case .table:
      try c.encode(columns, forKey: .columns)
      try c.encode(rows, forKey: .rows)
    case .control:
      try c.encode(title, forKey: .title); try c.encode(controlType, forKey: .controlType); try c.encode(binding, forKey: .binding)
    case .navigationLink:
      try c.encode(title, forKey: .title); try c.encode(destination, forKey: .destination)
    case .timeline:
      try c.encode(title, forKey: .title); try c.encode(events, forKey: .events)
    case .button:
      try c.encode(title, forKey: .title)
      try c.encode(action, forKey: .action)
    case .metric:
      try c.encode(label, forKey: .label); try c.encode(value, forKey: .value)
      try c.encodeIfPresent(valueBinding, forKey: .valueBinding)
      try c.encode(detail, forKey: .detail)
    case .iconList: try c.encode(iconItems, forKey: .iconItems)
    case .progress:
      try c.encode(title, forKey: .title); try c.encode(completed, forKey: .completed)
      try c.encode(total, forKey: .total)
    case .chart:
      try c.encode(title, forKey: .title); try c.encode(chartStyle, forKey: .chartStyle)
      try c.encode(points, forKey: .points)
    }
  }

}

public struct UIDocument: Codable, Sendable {
  public let version: Int
  public let root: UINode
  public let floatingActions: [UINode]
  public let state: [StateField]
  public let calculations: [CalculationBinding]
  public let records: [RecordCollection]
  private enum CodingKeys: String, CodingKey { case version, root, floatingActions, state, calculations, records }

  public init(from decoder: any Decoder) throws {
    try checkKeys(decoder, allowed: ["version", "root", "floatingActions", "state", "calculations", "records"])
    let values = try decoder.container(keyedBy: CodingKeys.self)
    records = values.contains(.records) ? try values.decode([RecordCollection].self, forKey: .records) : []
    calculations = values.contains(.calculations) ? try values.decode([CalculationBinding].self, forKey: .calculations) : []
    state = try values.decodeIfPresent([StateField].self, forKey: .state) ?? []
    version = try values.decode(Int.self, forKey: .version)
    root = try values.decode(UINode.self, forKey: .root)
    floatingActions =
      values.contains(.floatingActions)
      ? try values.decode([UINode].self, forKey: .floatingActions) : []
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(version, forKey: .version)
    try container.encode(root, forKey: .root)
    try container.encode(state, forKey: .state)
    try container.encode(floatingActions, forKey: .floatingActions)
    if !calculations.isEmpty { try container.encode(calculations, forKey: .calculations) }
    if !records.isEmpty { try container.encode(records, forKey: .records) }
  }

  /// Always validate against the registries that execute host capabilities.
  public static func decode(_ data: Data, registeredActions: Set<String>, registeredCalculations: Set<String> = []) throws -> UIDocument {
    guard data.count <= 65_536 else { throw UIError("JSON exceeds the 64 KiB limit.") }
    do {
      let document = try JSONDecoder().decode(Self.self, from: data)
      try document.validate(registeredActions: registeredActions, registeredCalculations: registeredCalculations)
      return document
    } catch let error as UIError {
      throw error
    } catch let error as DecodingError {
      switch error {
      case .keyNotFound(let key, let context):
        throw UIError("Missing '\(key.stringValue)' at \(location(context.codingPath)).")
      case .typeMismatch(_, let context), .valueNotFound(_, let context):
        throw UIError(
          "Invalid type or null at \(location(context.codingPath)): \(context.debugDescription)")
      case .dataCorrupted(let context):
        throw UIError(
          "Invalid JSON or enum value at \(location(context.codingPath)): \(context.debugDescription)"
        )
      @unknown default: throw UIError("Unable to decode UI JSON.")
      }
    } catch { throw UIError("Unable to decode UI JSON: \(error.localizedDescription)") }
  }

  public func validate(registeredActions: Set<String>, registeredCalculations: Set<String> = []) throws {
    guard version == 1 else { throw UIError("Unsupported version \(version); expected 1.") }
    guard floatingActions.count <= 3, floatingActions.allSatisfy({ $0.type == .button }) else {
      throw UIError("floatingActions accepts at most 3 buttons.")
    }
    try validateState()
    try validateRecords()
    let fields = Dictionary(uniqueKeysWithValues: state.map { ($0.id, $0) })
    let derivedFields = try validateCalculationBindings(fields: fields, registeredCalculations: registeredCalculations)
    var destinations = [String: UINode]()
    func index(_ node: UINode) { destinations[node.id] = node; node.children.forEach(index) }
    index(root)
    var ids = Set<String>()
    var count = 0
    func visit(_ node: UINode, depth: Int) throws {
      count += 1
      guard count <= 128, depth <= 12 else { throw UIError("UI exceeds 128 nodes or 12 levels.") }
      guard validIdentifier(node.id), ids.insert(node.id).inserted else {
        throw UIError(
          "Node ID '\(node.id)' must be unique and use 1–64 ASCII letters, digits, '.', '_' or '-'."
        )
      }
      guard node.spacing.isFinite, (0...48).contains(node.spacing), node.children.count <= 32 else {
        throw UIError("Invalid layout '\(node.id)': spacing must be 0–48 and children at most 32.")
      }
      guard node.text.count <= 4_000 else {
        throw UIError("Text '\(node.id)' exceeds 4000 characters.")
      }
      func bounded(_ text: String, _ maximum: Int) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && text.count <= maximum
      }
      guard (1...6).contains(node.columnCount) else { throw UIError("Grid needs 1–6 columns.") }
      if let icon = node.icon, !validIdentifier(icon) { throw UIError("Invalid icon key on '\(node.id)'.") }
      if node.type == .metric {
        guard bounded(node.label, 80), bounded(node.value, 80), node.detail.count <= 160 else {
          throw UIError("Metric needs bounded label, value and detail.")
        }
        if let binding = node.valueBinding {
          guard validIdentifier(binding), fields[binding]?.kind == .number else {
            throw UIError("Metric binding requires a declared numeric field.")
          }
        }
      }
      if node.type == .badge {
        guard bounded(node.text, 80) else { throw UIError("Badge needs 1–80 characters.") }
      }
      if node.type == .iconList {
        guard (1...32).contains(node.iconItems.count), node.iconItems.allSatisfy({
          bounded($0.text, 1000) && validIdentifier($0.icon)
        }) else { throw UIError("Icon list needs 1–32 bounded text and icon pairs.") }
      }
      if node.type == .progress {
        guard bounded(node.title, 160), node.total.isFinite, node.completed.isFinite,
          node.total > 0, node.total <= 1e9, (0...node.total).contains(node.completed)
        else { throw UIError("Progress needs finite 0 ≤ completed ≤ total, total > 0.") }
      }
      if node.type == .chart {
        if let source = node.recordSource {
          guard validIdentifier(source), (records.contains(where: { $0.id == source }) || calculations.contains(where: { $0.recordOutputs.values.contains(source) })),
            node.recordFields.count == 3, node.recordFields.allSatisfy(validIdentifier),
            node.points.allSatisfy({ $0.binding == nil }) else { throw UIError("Chart records require label, value, and series fields from one collection.") }
        } else if !node.recordFields.isEmpty { throw UIError("Record fields require a collection source.") }
        let series = Set(node.points.map(\.series))
        let keys = node.points.map { [$0.series, $0.label] }
        guard bounded(node.title, 160), (1...32).contains(node.points.count), series.count <= 4,
          Set(keys).count == keys.count, node.points.allSatisfy({
            bounded($0.label, 40) && bounded($0.series, 40) && $0.value.isFinite && abs($0.value) <= 1e9
          }) else { throw UIError("Chart needs 1–32 finite, unique labeled points, at most 4 series.") }
        for point in node.points {
          if let binding = point.binding {
            guard fields[binding]?.kind == .number else { throw UIError("Chart binding requires a declared numeric field.") }
          }
        }
        if node.chartStyle == .donut {
          guard series.count == 1, node.points.allSatisfy({ $0.value >= 0 }),
            node.points.reduce(0, { $0 + $1.value }) > 0 else { throw UIError("Donut requires one nonnegative series with positive total.") }
        }
        if node.chartStyle == .radar {
          guard series.count == 1, (3...8).contains(node.points.count),
            node.points.allSatisfy({ (0...100).contains($0.value) })
          else { throw UIError("Radar requires one series with 3–8 values in 0–100.") }
        }
      }
      if node.type == .text && !node.binding.isEmpty {
        guard fields[node.binding]?.kind == .text else { throw UIError("Text output requires a declared text field.") }
      }
      if node.type == .control {
        guard bounded(node.title, 160), let field = fields[node.binding] else { throw UIError("Control '\(node.id)' needs a declared state binding '\(node.binding)' and a bounded title. Include every control's state field, including choice options.") }
        let expected: StateField.Kind = switch node.controlType {
        case .toggle: .boolean
        case .slider, .stepper: .number
        case .picker: .choice
        case .datePicker: .date
        case .textField, .textEditor: .text
        }
        guard !derivedFields.contains(node.binding) else { throw UIError("Controls cannot edit derived fields.") }
        guard field.kind == expected, expected != .number || field.minimum < field.maximum else { throw UIError("Control '\(node.id)' has the wrong binding type.") }
      }
      if node.type == .navigationLink {
        guard bounded(node.title, 160), let target = destinations[node.destination], target.type == .section, target.id != root.id else { throw UIError("Navigation requires an existing non-root section destination.") }
        func links(_ n: UINode) -> Bool { n.type == .navigationLink || n.children.contains(where: links) }
        guard !links(target) else { throw UIError("Navigation destinations cannot contain further links (cycles are forbidden).") }
      }
      if node.type == .timeline {
        if let source = node.recordSource {
          guard validIdentifier(source), records.contains(where: { $0.id == source }) || calculations.contains(where: { $0.recordOutputs.values.contains(source) }),
            node.recordFields.count == 3, node.recordFields.allSatisfy(validIdentifier),
            node.events.allSatisfy({ $0.timeBinding == nil && $0.detailBinding == nil }) else {
            throw UIError("Timeline records require time, title, and detail fields from one collection.")
          }
        } else if !node.recordFields.isEmpty { throw UIError("Record fields require a collection source.") }
        for event in node.events {
          for binding in [event.timeBinding, event.detailBinding].compactMap({ $0 }) {
            guard fields[binding]?.kind == .text else { throw UIError("Timeline output requires a declared text field.") }
          }
        }
        guard bounded(node.title, 160), (1...32).contains(node.events.count), node.events.allSatisfy({ bounded($0.time, 80) && bounded($0.title, 160) && $0.detail.count <= 1000 }) else { throw UIError("Timeline requires 1–32 bounded events.") }
      }
      if node.type == .section || node.type == .form {
        guard !node.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          node.title.count <= 160
        else { throw UIError("Section '\(node.id)' needs a title of 1–160 characters.") }
      }
      if node.type == .list {
        if let source = node.recordSource {
          guard validIdentifier(source), (records.contains(where: { $0.id == source }) || calculations.contains(where: { $0.recordOutputs.values.contains(source) })),
            node.recordFields.count == 1, node.recordFields.allSatisfy(validIdentifier) else {
            throw UIError("List records require a declared collection and one text field.")
          }
        } else if !node.recordFields.isEmpty { throw UIError("Record fields require a collection source.") }
        guard (1...32).contains(node.items.count),
          node.items.allSatisfy({
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 1000
          })
        else {
          throw UIError(
            "List '\(node.id)' needs 1–32 nonempty items, at most 1000 characters each.")
        }
      }
      if node.type == .table {
        if !node.editableFields.isEmpty {
          guard let source = node.recordSource, let collection = records.first(where: { $0.id == source }),
            Set(node.editableFields).count == node.editableFields.count,
            node.editableFields.allSatisfy({ node.recordFields.contains($0) && collection.schema.fields[$0] != nil }) else {
            throw UIError("Editable table fields require declared source record fields.")
          }
        }
        if let source = node.recordSource {
          guard validIdentifier(source), (records.contains(where: { $0.id == source }) || calculations.contains(where: { $0.recordOutputs.values.contains(source) })),
            node.recordFields.count == node.columns.count, node.recordFields.allSatisfy(validIdentifier) else {
            throw UIError("Table records require a declared collection and one field per column.")
          }
        } else if !node.recordFields.isEmpty { throw UIError("Record fields require a collection source.") }
        guard (1...6).contains(node.columns.count), (1...32).contains(node.rows.count),
          node.columns.allSatisfy({ !$0.isEmpty && $0.count <= 80 }),
          node.rows.allSatisfy({
            $0.count == node.columns.count && $0.allSatisfy { $0.count <= 1000 }
          })
        else {
          throw UIError(
            "Table '\(node.id)' needs 1–6 columns, 1–32 rectangular rows and bounded cells.")
        }
      }
      if node.type == .button {
        guard !node.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          node.title.count <= 80
        else {
          throw UIError("Button '\(node.id)' needs a title of 1–80 characters.")
        }
        guard validIdentifier(node.action), registeredActions.contains(node.action) else {
          throw UIError(
            "Unknown action '\(node.action)' on '\(node.id)'. Register a host callback first.")
        }
      }
      for child in node.children { try visit(child, depth: depth + 1) }
    }
    try visit(root, depth: 1)
    for node in floatingActions { try visit(node, depth: 1) }
    if calculations.isEmpty {
      try validateRecordProjectionSchemas(Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0.schema) }))
      try validatePresentation(values: Dictionary(uniqueKeysWithValues: state.map { ($0.id, $0.value) }),
        records: Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0.rows) }))
    }
  }
}

func validIdentifier(_ value: String) -> Bool {
  !value.isEmpty && value.utf8.count <= 64
    && value.utf8.allSatisfy {
      (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0)
        || [45, 46, 95].contains($0)
    }
}
