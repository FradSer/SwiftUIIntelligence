import Foundation

extension UINode {
  /// Resolve a numeric metric without units or locale-dependent rounding. Static metrics keep their exact text.
  public func resolvedMetricValue(values: [String: StateValue]) throws -> String {
    guard let valueBinding else { return value }
    guard case .number(let number) = values[valueBinding], number.isFinite, abs(number) <= 1e9 else {
      throw UIError("Metric binding requires a finite numeric value within ±1e9.")
    }
    let display = String(number)
    return display.hasSuffix(".0") ? String(display.dropLast(2)) : display
  }

  public func resolvedPoints(values: [String: StateValue], records: [String: [RecordRow]] = [:]) throws -> [ChartPoint] {
    let resolved: [ChartPoint]
    if let recordSource {
      guard let rows = records[recordSource], recordFields.count == 3 else { throw UIError("Chart records are not available.") }
      resolved = try rows.map { row in
        guard case .text(let label) = row.values[recordFields[0]],
          case .number(let value) = row.values[recordFields[1]],
          case .text(let series) = row.values[recordFields[2]] else { throw UIError("Chart record fields have incompatible types.") }
        return ChartPoint(label: label, value: value, series: series)
      }
      if resolved.isEmpty { return [] }
    } else {
      resolved = try points.map { try $0.resolved(in: values) }
    }
    let series = Set(resolved.map(\.series))
    guard resolved.count <= 32, series.count <= 4,
      Set(resolved.map { [$0.series, $0.label] }).count == resolved.count,
      resolved.allSatisfy({ !$0.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.label.count <= 40
        && !$0.series.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.series.count <= 40
        && $0.value.isFinite && abs($0.value) <= 1e9 }) else { throw UIError("Invalid resolved chart records.") }
    let numbers = resolved.map(\.value)
    if chartStyle == .donut {
      guard series.count == 1, numbers.allSatisfy({ $0 >= 0 }), numbers.reduce(0, +) > 0 else {
        throw UIError("Donut requires nonnegative values with a positive total.")
      }
    }
    if chartStyle == .radar {
      guard series.count == 1, (3...8).contains(numbers.count), numbers.allSatisfy({ (0...100).contains($0) }) else {
        throw UIError("Radar values must remain in 0–100.")
      }
    }
    return resolved
  }
}

extension UIDocument {
  func validatePresentation(values: [String: StateValue], records: [String: [RecordRow]] = [:]) throws {
    func visit(_ node: UINode) throws {
      if node.type == .metric {
        _ = try node.resolvedMetricValue(values: values)
      }
      if node.type == .chart {
        _ = try node.resolvedPoints(values: values, records: records)
      }
      if node.type == .list && node.recordSource != nil {
        _ = try node.resolvedItems(in: records)
      }
      if node.type == .table && node.recordSource != nil {
        _ = try node.resolvedRows(in: records)
      }
      if node.type == .timeline {
        for event in try node.resolvedEvents(in: records) {
          _ = try event.resolvedTime(in: values)
          _ = try event.resolvedDetail(in: values)
        }
      }
      try node.children.forEach(visit)
    }
    try visit(root)
  }
}
