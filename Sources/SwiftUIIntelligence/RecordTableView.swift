import SwiftUI

struct RecordTableView: View {
  @Environment(DocumentState.self) private var state
  let node: UINode

  var body: some View {
    if let source = node.recordSource, let rows = state.records[source] {
      VStack(alignment: .leading, spacing: 16) {
        if rows.isEmpty { Text("No matching items.") }
        ForEach(rows) { row in
          VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(node.recordFields.enumerated()), id: \.offset) { index, field in
              if let value = row.values[field] {
                cell(source: source, row: row.id, field: field, column: index, label: node.columns[index], value: value)
              }
            }
          }
          if row.id != rows.last?.id { Divider() }
        }
        if let error = state.errorMessage { Text(error).font(.callout).accessibilityIdentifier(node.id + "-edit-error") }
      }
    }
  }

  @ViewBuilder private func cell(source: String, row: String, field: String, column: Int, label: String, value: StateValue) -> some View {
    if node.editableFields.contains(field) {
      switch value {
      case .text(let text):
        TextField(label, text: Binding(get: {
          if case .text(let current) = current(source, row, field) { return current }
          return text
        }, set: { update(source, row, field, .text($0)) }))
          .accessibilityLabel(label).accessibilityIdentifier(identifier(row, field, column))
      case .number(let number):
        LabeledContent(label) {
          TextField(label, value: Binding(get: {
            if case .number(let current) = current(source, row, field) { return current }
            return number
          }, set: { update(source, row, field, .number($0)) }), format: .number)
            .multilineTextAlignment(.trailing).accessibilityIdentifier(identifier(row, field, column))
        }
      case .boolean(let enabled):
        Toggle(label, isOn: Binding(get: {
          if case .boolean(let current) = current(source, row, field) { return current }
          return enabled
        }, set: { update(source, row, field, .boolean($0)) }))
          .accessibilityIdentifier(identifier(row, field, column))
      }
    } else {
      LabeledContent(label) {
        Text(display(value)).accessibilityIdentifier(identifier(row, field, column))
      }
    }
  }

  private func identifier(_ row: String, _ field: String, _ column: Int) -> String {
    "\(node.id):\(row):\(field):\(column)"
  }
  private func current(_ source: String, _ row: String, _ field: String) -> StateValue? {
    state.records[source]?.first(where: { $0.id == row })?.values[field]
  }
  private func update(_ source: String, _ row: String, _ field: String, _ value: StateValue) {
    state.editRecord(source, row: row, field: field, to: value)
  }
  private func display(_ value: StateValue) -> String {
    switch value {
    case .text(let text): text
    case .number(let number): String(number)
    case .boolean(let enabled): enabled ? "True" : "False"
    }
  }
}
