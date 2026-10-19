import Charts
import SwiftUI

struct SymbolText: View {
  let text: String
  let icon: String?
  var tint: Color? = nil
  var body: some View {
    HStack(alignment: .center, spacing: 10) {
      if let icon {
        let symColor = tint ?? Self.accentColor(for: icon) ?? .primary
        Image(systemName: SymbolCatalog.systemName(for: icon))
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(symColor)
          .frame(width: 28, height: 28)
          .background(symColor.opacity(symColor == .primary ? 0.08 : 0.14), in: Circle())
          .accessibilityHidden(true)
      }
      Text(text).fixedSize(horizontal: false, vertical: true)
    }
  }

  private static func accentColor(for key: String) -> Color? {
    let lower = key.lowercased()
    if lower.contains("food") || lower.contains("meal") || lower.contains("cart") || lower.contains("money") || lower.contains("receipt") {
      return .green
    }
    if lower.contains("slider") || lower.contains("tune") || lower.contains("filter") || lower.contains("temp") {
      return .orange
    }
    if lower.contains("check") || lower.contains("list") || lower.contains("water") || lower.contains("drop") {
      return .blue
    }
    if lower.contains("time") || lower.contains("calendar") || lower.contains("schedule") || lower.contains("tag") || lower.contains("ruler") || lower.contains("scale") {
      return .purple
    }
    return nil
  }
}

struct PresentationNodeView: View {
  @Environment(DocumentState.self) private var state
  private var resolvedPoints: [ChartPoint]? { try? node.resolvedPoints(values: state.values, records: state.records) }
  let node: UINode
  var showsTitle = true
  @Environment(\.colorScheme) private var colorScheme
  @State private var selectedLabel: String?
  private var colors: [Color] {
    colorScheme == .dark ? [.cyan, .mint, .orange, .pink, .purple] : [.blue, .green, .orange, .purple, .teal]
  }
  @ViewBuilder var body: some View {
    switch node.type {
    case .metric:
      let metricValue = (try? node.resolvedMetricValue(values: state.values)) ?? node.value
      let cardTint = (node.cardColor ?? .neutral).swiftUIColor != .primary ? (node.cardColor ?? .neutral).swiftUIColor : nil
      VStack(alignment: .leading, spacing: 8) {
        SymbolText(text: node.label, icon: node.icon, tint: cardTint).font(.caption).lineLimit(2).minimumScaleFactor(0.85).foregroundStyle(.secondary).frame(minHeight: 32, alignment: .topLeading)
        Text(metricValue).font(.title2).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
        if !node.detail.isEmpty && node.detail != metricValue { Text(node.detail).font(.caption).foregroundStyle(.secondary) }
      }.frame(maxWidth: .infinity, alignment: .leading)
    case .iconList:
      VStack(alignment: .leading, spacing: 12) {
        ForEach(Array(node.iconItems.enumerated()), id: \.offset) { _, item in
          SymbolText(text: item.text, icon: item.icon).frame(maxWidth: .infinity, alignment: .leading)
        }
      }
    case .badge:
      let tint = (node.cardColor?.swiftUIColor ?? toneColor)
      HStack(spacing: 5) {
        if let icon = node.icon {
          Image(systemName: SymbolCatalog.systemName(for: icon))
            .font(.caption2.weight(.semibold))
        }
        Text(node.text).font(.caption.weight(.medium))
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background(Capsule().fill(tint.opacity(0.12)))
      .foregroundStyle(tint)
      .accessibilityLabel("\(node.tone.rawValue): \(node.text)")
    case .progress:
      let cardTint = (node.cardColor ?? .neutral).swiftUIColor != .primary ? (node.cardColor ?? .neutral).swiftUIColor : nil
      VStack(alignment: .leading, spacing: 10) {
        SymbolText(text: node.title, icon: node.icon, tint: cardTint).font(.headline)
        ProgressView(value: node.completed, total: node.total)
        Text("\(node.completed.formatted()) / \(node.total.formatted()) · \((node.completed / node.total).formatted(.percent.precision(.fractionLength(0))))")
          .font(.caption).foregroundStyle(.secondary).monospacedDigit()
      }.accessibilityElement(children: .combine)
    case .chart:
      if let points = resolvedPoints {
      VStack(alignment: .leading, spacing: 12) {
        if showsTitle { Text(node.title).font(.headline) }
        if points.isEmpty { Text("No matching items.") }
        else {
        if node.chartStyle == .radar {
          RadarNodeView(points: points, color: colors[0]).frame(height: 220).frame(minWidth: 180)
        } else {
          chart(points: points).frame(height: 210).frame(minWidth: 180)
          if let selectedLabel, points.contains(where: { $0.label == selectedLabel }) {
            Text(points.filter { $0.label == selectedLabel }.map {
              "\($0.label) · \($0.series): \($0.value.formatted())"
            }.joined(separator: "\n")).font(.caption).accessibilityIdentifier(node.id + "-selection")
          }
        }
        // Visible values accompany color, chart axes and VoiceOver; charts never hide data.
        if node.chartStyle == .donut {
          ForEach(Array(points.enumerated()), id: \.offset) { index, point in
            HStack {
              Circle().fill(colors[index % colors.count]).frame(width: 8, height: 8).accessibilityHidden(true)
              Text(point.label); Spacer(); Text(point.value.formatted()).monospacedDigit()
            }.font(.caption)
          }
        }
      }
      }
      } else {
        Text("Chart values are not available.").accessibilityIdentifier(node.id + "-unavailable")
      }
    default: EmptyView()
    }
  }
  private var toneColor: Color { node.tone == .warning ? .orange : node.tone == .success ? .green : .blue }
  private func chart(points: [ChartPoint]) -> some View {
    Chart {
      ForEach(Array(points.enumerated()), id: \.offset) { _, point in
        if node.chartStyle == .donut {
          SectorMark(angle: .value("Value", point.value), innerRadius: .ratio(0.72), angularInset: 1)
            .foregroundStyle(by: .value("Category", point.label))
        } else if node.chartStyle == .bar {
          BarMark(x: .value("Label", point.label), y: .value("Value", point.value))
            .foregroundStyle(by: .value("Series", point.series)).position(by: .value("Series", point.series))
            .accessibilityLabel("\(point.label), \(point.series)")
            .accessibilityValue(point.value.formatted())
        } else {
          if node.chartStyle == .area {
            AreaMark(x: .value("Label", point.label), y: .value("Value", point.value), series: .value("Series", point.series))
              .foregroundStyle(by: .value("Series", point.series)).opacity(0.16)
          }
          LineMark(x: .value("Label", point.label), y: .value("Value", point.value), series: .value("Series", point.series))
            .foregroundStyle(by: .value("Series", point.series))
          PointMark(x: .value("Label", point.label), y: .value("Value", point.value))
            .foregroundStyle(by: .value("Series", point.series))
        }
      }
      if node.chartStyle != .donut, let selectedLabel, points.contains(where: { $0.label == selectedLabel }) {
        RuleMark(x: .value("Label", selectedLabel)).foregroundStyle(.secondary)
      }
    }
    .chartForegroundStyleScale(range: colors)
    .chartLegend(node.chartStyle == .donut ? .hidden : .visible)
    .chartXSelection(value: $selectedLabel)
    .accessibilityLabel(node.title)
    .accessibilityChildren {
      ForEach(Array(points.enumerated()), id: \.offset) { _, point in
        Text("\(point.label), \(point.series)")
          .accessibilityValue(point.value.formatted())
      }
    }
  }
}

private struct RadarNodeView: View {
  let points: [ChartPoint]
  let color: Color
  var body: some View {
    GeometryReader { geometry in
      let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
      let radius = min(geometry.size.width, geometry.size.height) * 0.34
      ZStack {
        ForEach(1...4, id: \.self) { level in
          polygon(center, radius, Array(repeating: Double(level) * 25, count: points.count))
            .stroke(.secondary.opacity(0.25), lineWidth: 0.7)
        }
        ForEach(Array(points.enumerated()), id: \.offset) { index, point in
          Text(point.label).font(.caption2).foregroundStyle(.secondary)
            .position(position(index, 138, center, radius))
        }
        polygon(center, radius, points.map(\.value)).fill(color.opacity(0.12))
        polygon(center, radius, points.map(\.value)).stroke(color, lineWidth: 2)
      }
    }.accessibilityElement(children: .ignore)
      .accessibilityLabel(points.map { "\($0.label): \($0.value.formatted()) out of 100" }.joined(separator: ", "))
  }
  private func position(_ index: Int, _ value: Double, _ center: CGPoint, _ radius: Double) -> CGPoint {
    let angle = Double(index) / Double(points.count) * .pi * 2 - .pi / 2
    return CGPoint(x: center.x + cos(angle) * radius * value / 100, y: center.y + sin(angle) * radius * value / 100)
  }
  private func polygon(_ center: CGPoint, _ radius: Double, _ values: [Double]) -> Path {
    Path { path in
      for index in values.indices {
        let point = position(index, values[index], center, radius)
        if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
      }
      path.closeSubpath()
    }
  }
}
