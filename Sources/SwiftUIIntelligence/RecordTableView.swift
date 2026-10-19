import SwiftUI

struct RecordTableView: View {
  @Environment(DocumentState.self) private var state
  let node: UINode

  var body: some View {
    if let source = node.recordSource, let rows = state.records[source] {
      VStack(alignment: .leading, spacing: 16) {
        if rows.isEmpty { Text("No matching items.") }
        ForEach(rows) { row in
          rowView(source: source, row: row)
          if row.id != rows.last?.id { Divider() }
        }
        if let error = state.errorMessage { Text(error).font(.callout).accessibilityIdentifier(node.id + "-edit-error") }
      }
    }
  }

  @ViewBuilder private func rowView(source: String, row: RecordRow) -> some View {
    // If the table displays exactly two fields (one primary name/title and one value/editor),
    // format them concisely on a single horizontal row like Apple Settings / Home rows.
    let presentFields = node.recordFields.filter { row.values[$0] != nil }
    if presentFields.count == 2,
       let nameIndex = node.recordFields.firstIndex(where: {
         let f = $0.lowercased()
         return f == "name" || f == "title" || f == "item" || f == "person" || f == "itemid" || f == "personid"
       }),
       let valueIndex = node.recordFields.firstIndex(where: { $0 != node.recordFields[nameIndex] }),
       let nameVal = row.values[node.recordFields[nameIndex]],
       let val = row.values[node.recordFields[valueIndex]] {
      let nameField = node.recordFields[nameIndex]
      let valField = node.recordFields[valueIndex]
      HStack(alignment: .center, spacing: 12) {
        VStack(alignment: .leading, spacing: 2) {
          Text(display(nameVal))
            .font(.body.weight(.medium))
            .foregroundStyle(.primary)
            .accessibilityIdentifier(identifier(row.id, nameField, nameIndex))
        }
        Spacer(minLength: 16)
        cellControl(source: source, row: row.id, field: valField, column: valueIndex, label: cleanLabel(node.columns[valueIndex]), value: val)
      }
    } else {
      VStack(alignment: .leading, spacing: 10) {
        ForEach(Array(node.recordFields.enumerated()), id: \.offset) { index, field in
          if let value = row.values[field] {
            cell(source: source, row: row.id, field: field, column: index, label: node.columns[index], value: value)
          }
        }
      }
    }
  }

  @ViewBuilder private func cellControl(source: String, row: String, field: String, column: Int, label: String, value: StateValue) -> some View {
    if node.editableFields.contains(field) && !isReferenceValue(value) {
      switch value {
      case .text(let text):
        TextField(label, text: Binding(get: {
          if case .text(let current) = current(source, row, field) { return current }
          return text
        }, set: { update(source, row, field, .text($0)) }))
          .multilineTextAlignment(.trailing)
          .accessibilityLabel(label).accessibilityIdentifier(identifier(row, field, column))
      case .number(let number):
        TextField(label, value: Binding(get: {
          if case .number(let current) = current(source, row, field) { return current }
          return number
        }, set: { update(source, row, field, .number($0)) }), format: .number)
          .multilineTextAlignment(.trailing)
          .frame(minWidth: 80, maxWidth: 120)
          .textFieldStyle(.roundedBorder)
          .accessibilityLabel(label).accessibilityIdentifier(identifier(row, field, column))
      case .boolean(let enabled):
        Toggle(label, isOn: Binding(get: {
          if case .boolean(let current) = current(source, row, field) { return current }
          return enabled
        }, set: { update(source, row, field, .boolean($0)) }))
          .labelsHidden()
          .accessibilityIdentifier(identifier(row, field, column))
      }
    } else {
      Text(display(value))
        .font(.body.monospacedDigit())
        .foregroundStyle(.secondary)
        .accessibilityIdentifier(identifier(row, field, column))
    }
  }

  @ViewBuilder private func cell(source: String, row: String, field: String, column: Int, label: String, value: StateValue) -> some View {
    let displayLabel = cleanLabel(label)
    if node.editableFields.contains(field) && !isReferenceValue(value) {
      switch value {
      case .text(let text):
        TextField(displayLabel, text: Binding(get: {
          if case .text(let current) = current(source, row, field) { return current }
          return text
        }, set: { update(source, row, field, .text($0)) }))
          .accessibilityLabel(displayLabel).accessibilityIdentifier(identifier(row, field, column))
      case .number(let number):
        LabeledContent(displayLabel) {
          TextField(displayLabel, value: Binding(get: {
            if case .number(let current) = current(source, row, field) { return current }
            return number
          }, set: { update(source, row, field, .number($0)) }), format: .number)
            .multilineTextAlignment(.trailing).accessibilityIdentifier(identifier(row, field, column))
        }
      case .boolean(let enabled):
        Toggle(displayLabel, isOn: Binding(get: {
          if case .boolean(let current) = current(source, row, field) { return current }
          return enabled
        }, set: { update(source, row, field, .boolean($0)) }))
          .accessibilityIdentifier(identifier(row, field, column))
      }
    } else {
      LabeledContent(displayLabel) {
        Text(display(value)).accessibilityIdentifier(identifier(row, field, column))
      }
    }
  }

  private func cleanLabel(_ label: String) -> String {
    let lower = label.lowercased()
    if lower == "item id" || lower == "itemid" { return "Item" }
    if lower == "person id" || lower == "personid" { return "Person" }
    if lower == "product id" || lower == "productid" { return "Product" }
    if lower == "amountminor" { return "Amount" }
    if lower == "foodminor" { return "Food Share" }
    if lower == "feeminor" { return "Service Fee" }
    if lower == "totalminor" { return "Total" }
    if lower == "payableminor" { return "Payable Total" }
    return label
  }

  private func isReferenceValue(_ value: StateValue) -> Bool {
    guard case .text(let text) = value else { return false }
    for (_, rows) in state.records {
      if rows.contains(where: { $0.id == text && $0.values["name"] != nil }) {
        return true
      }
    }
    return false
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
    case .text(let text):
      for (_, collectionRows) in state.records {
        if let target = collectionRows.first(where: { $0.id == text }),
           case .text(let name) = target.values["name"] {
          return name
        }
      }
      return text
    case .number(let number):
      if number.rounded() == number && abs(number) < 1e15 {
        return String(Int64(number))
      }
      return String(number)
    case .boolean(let enabled): return enabled ? "True" : "False"
    }
  }
}
