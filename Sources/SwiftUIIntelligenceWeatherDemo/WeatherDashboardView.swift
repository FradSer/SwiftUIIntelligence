import SwiftUIIntelligence
import Charts
import SwiftUI

private enum WeatherPalette {
  static let border = Color.primary.opacity(0.15)
  static func blue(for scheme: ColorScheme) -> Color { .blue }
  static func low(for scheme: ColorScheme) -> Color { .purple }
  static let muted = Color.secondary
}

struct WeatherDashboardView: View {
  let weather: WeatherData
  let stage: Int
  @Environment(\.colorScheme) private var colorScheme
  private var chartBlue: Color { WeatherPalette.blue(for: colorScheme) }
  private var chartLow: Color { WeatherPalette.low(for: colorScheme) }
  private var windColors: [Color] { [.blue, .purple, .green, .orange, .pink] }
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @State private var selectedDay: Int?
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    if stage == 0 {
      VStack(spacing: 14) {
        Image(systemName: "desktopcomputer").font(.title2)
        Text("Rendered UI will appear here").font(.callout)
      }
      .foregroundStyle(.secondary)
      .padding(20)
      
      .frame(maxWidth: .infinity, minHeight: 280)
      .accessibilityIdentifier("empty-preview")
    } else {
      GeometryReader { geometry in
        let compact = geometry.size.width < 560
        ScrollViewReader { proxy in
          ScrollView {
            GlassEffectContainer {
              VStack(alignment: .leading, spacing: 8) {
                heading
                if stage >= 2 { metrics(compact: compact) }
                if stage >= 3 {
                  if stage == 3 {
                    temperatureChart
                  } else {
                    HStack(alignment: .top, spacing: 8) {
                      temperatureChart
                      precipitationChart
                    }
                  }
                }
                if stage >= 5 {
                  Group {
                    if compact {
                      hourlyTable
                      HStack(alignment: .top, spacing: 8) {
                        radarCard
                        windCard
                      }
                    } else {
                      HStack(alignment: .top, spacing: 8) {
                        hourlyTable
                        radarCard
                        windCard
                      }
                    }
                  }
                  .id("weather-details")
                }
              }
              .padding(12)
            }
          }
          .clipped()
          .accessibilityIdentifier("weather-scroll")
          .onChange(of: stage, initial: true) { _, value in
            if value == 6 {
              withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.8)) {
                proxy.scrollTo("weather-details", anchor: .top)
              }
            }
          }
        }
      }
    }
  }

  private var heading: some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: 10) {
        title
        Text(weather.subtitle).font(.caption)
        liveTag
      }
      VStack(alignment: .leading, spacing: 6) {
        title
        HStack {
          Text(weather.subtitle).font(.caption)
          liveTag
        }
      }
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .cardSurface()
    .accessibilityIdentifier("weather-heading")
  }

  private var title: some View {
    Label(weather.title, systemImage: "cloud.sun.fill").font(.subheadline)
  }

  private var liveTag: some View {
    Text("Live").font(.caption2).foregroundStyle(.primary)
      .padding(.horizontal, 5).padding(.vertical, 2)
      
      .accessibilityLabel("Live styling from reference; fixed example data")
  }

  private func metrics(compact: Bool) -> some View {
    LazyVGrid(
      columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: dynamicTypeSize.isAccessibilitySize ? (compact ? 1 : 2) : (compact ? 3 : 6)),
      spacing: 8
    ) {
      ForEach(weather.metrics) { metric in
        VStack(alignment: .leading, spacing: 8) {
          Text(metric.value).font(.subheadline).monospacedDigit()
          Text(metric.label).font(.caption).foregroundStyle(WeatherPalette.muted).fixedSize(
            horizontal: false, vertical: true)
          Text(metric.detail).font(.caption2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 5).padding(.vertical, 3)
            .accessibilityIdentifier("\(metric.id)-detail")

          Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
        .padding(12)
        .cardSurface()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(metric.id)
      }
    }
  }

  private var temperatureChart: some View {
    chartCard("7-Day Temperature Forecast", id: "temperature-chart") {
      Chart {
        ForEach(Array(weather.days.enumerated()), id: \.element.id) { index, day in
          LineMark(
            x: .value("Day", index), y: .value("Temperature", day.high),
            series: .value("Series", "High")
          )
          .interpolationMethod(.catmullRom).foregroundStyle(by: .value("Series", "High"))
          LineMark(
            x: .value("Day", index), y: .value("Temperature", day.low),
            series: .value("Series", "Low")
          )
          .interpolationMethod(.catmullRom).foregroundStyle(by: .value("Series", "Low"))
        }
        if let selectedDay, weather.days.indices.contains(selectedDay) {
          RuleMark(x: .value("Day", selectedDay)).foregroundStyle(.secondary)
            .annotation(position: .top) {
              Text(
                "\(weather.days[selectedDay].label): \(Int(weather.days[selectedDay].high))° / \(Int(weather.days[selectedDay].low))°"
              )
              .font(.caption2).padding(8)
              
            }
        }
      }
      .chartForegroundStyleScale(["High": chartBlue, "Low": chartLow])
      .chartYScale(domain: 0...90)
      .chartXSelection(value: $selectedDay)
      .weatherAxes(days: weather.days, yValues: [0, 20, 40, 60, 80])
      .chartLegend(position: .bottom, alignment: .center, spacing: 12)
    }
  }

  private var precipitationChart: some View {
    chartCard("Precipitation (mm)", id: "precipitation-chart") {
      Chart(Array(weather.days.enumerated()), id: \.element.id) { index, day in
        AreaMark(x: .value("Day", index), y: .value("Precipitation", day.precipitation))
          .interpolationMethod(.catmullRom)
          .foregroundStyle(
            chartBlue.opacity(0.15))
        LineMark(x: .value("Day", index), y: .value("Precipitation", day.precipitation))
          .interpolationMethod(.catmullRom).foregroundStyle(chartBlue)
      }
      .chartYScale(domain: 0...18)
      .weatherAxes(days: weather.days, yValues: [0, 4, 8, 12, 16])
      HStack(spacing: 5) {
        Rectangle().fill(chartBlue).frame(width: 7, height: 7)
        Text("Precipitation")
      }
      .font(.caption2).frame(maxWidth: .infinity)
    }
  }

  private func chartCard<C: View>(_ name: String, id: String, @ViewBuilder content: () -> C)
    -> some View
  {
    VStack(alignment: .leading, spacing: 12) {
      Text(name).font(.subheadline)
      VStack(spacing: 8) { content() }.font(.caption2).frame(height: 220)
    }
    .padding(14).frame(maxWidth: .infinity, alignment: .leading).cardSurface()
    .accessibilityIdentifier(id)
  }

  private var hourlyTable: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Hourly Forecast").font(.subheadline)
      HStack {
        Text("Time")
        Spacer()
        Text("Condition")
        Spacer()
        Text("°F")
      }
      .font(.caption2).foregroundStyle(WeatherPalette.muted)
      ForEach(weather.hours) { hour in
        HStack(spacing: 5) {
          Text(hour.time).frame(width: 44, alignment: .leading)
          Label(hour.condition.rawValue, systemImage: hour.condition.symbol)
            .labelStyle(.titleAndIcon).lineLimit(1)
          Spacer(minLength: 0)
          Text("\(Int(hour.temperature))").monospacedDigit()
        }
        .font(.caption2).padding(.vertical, 6)
        .overlay(alignment: .bottom) { Rectangle().fill(WeatherPalette.border).frame(height: 0.5) }
        .accessibilityIdentifier(hour.id)
      }
      Spacer(minLength: 0)
    }
    .padding(14).frame(maxWidth: .infinity, minHeight: 370, alignment: .topLeading).cardSurface()
    .accessibilityIdentifier("hourly-forecast")
  }

  private var radarCard: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Conditions Breakdown").font(.subheadline)
      RadarChart(values: weather.conditions).frame(height: 165)
      HStack(spacing: 6) {
        Rectangle().fill(chartBlue).frame(width: 7, height: 7)
        Text("Today").font(.caption2)
      }
      .frame(maxWidth: .infinity)
      Spacer(minLength: 0)
    }
    .padding(14).frame(maxWidth: .infinity, minHeight: 370, alignment: .topLeading).cardSurface()
    .accessibilityIdentifier("conditions-breakdown")
  }

  private var windCard: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Wind Distribution").font(.subheadline)
      Chart(weather.wind) { wind in
        SectorMark(
          angle: .value("Percent", wind.value), innerRadius: .ratio(0.88), angularInset: 0.4
        )
        .foregroundStyle(by: .value("Direction", wind.label))
      }
      .chartForegroundStyleScale(range: windColors)
      .chartLegend(.hidden).frame(height: 160)
      ForEach(Array(weather.wind.enumerated()), id: \.element.id) { index, wind in
        HStack(spacing: 8) {
          Rectangle().fill(windColors[index % windColors.count])
            .frame(width: 7, height: 7)
          Text(wind.label)
          Spacer()
          Text("\(wind.value, format: .number.precision(.fractionLength(1)))%")
        }.font(.caption2).monospacedDigit()
      }
      VStack(alignment: .leading, spacing: 3) {
        Text("Forecast Summary").foregroundStyle(chartLow)
        Text(weather.summary).fixedSize(horizontal: false, vertical: true)
      }
      .font(.caption2).padding(.leading, 8)
      .overlay(alignment: .leading) { Rectangle().fill(chartBlue).frame(width: 1) }
    }
    .padding(14).frame(maxWidth: .infinity, minHeight: 370, alignment: .topLeading).cardSurface()
    .accessibilityIdentifier("wind-distribution")
  }
}

private struct RadarChart: View {
  let values: [WeatherValue]
  @Environment(\.colorScheme) private var colorScheme
  private var chartBlue: Color { WeatherPalette.blue(for: colorScheme) }
  var body: some View {
    GeometryReader { g in
      let center = CGPoint(x: g.size.width / 2, y: g.size.height / 2)
      let radius = min(g.size.width, g.size.height) * 0.35
      ZStack {
        ForEach(1...4, id: \.self) { level in
          polygon(
            center: center, radius: radius * Double(level) / 4,
            values: Array(repeating: 100, count: values.count)
          )
          .stroke(WeatherPalette.border, lineWidth: 0.7)
        }
        ForEach(Array(values.enumerated()), id: \.element.id) { index, value in
          let end = point(index: index, value: 100, center: center, radius: radius)
          Path {
            $0.move(to: center)
            $0.addLine(to: end)
          }.stroke(WeatherPalette.border, lineWidth: 0.7)
          Text(value.label).font(.caption2).foregroundStyle(WeatherPalette.muted)
            .position(point(index: index, value: 132, center: center, radius: radius))
        }
        polygon(center: center, radius: radius, values: values.map(\.value))
          .fill(chartBlue.opacity(0.08))
        polygon(center: center, radius: radius, values: values.map(\.value))
          .stroke(chartBlue, lineWidth: 1.5)
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      values.map { "\($0.label): \(Int($0.value)) out of 100" }.joined(separator: ", "))
  }
  private func point(index: Int, value: Double, center: CGPoint, radius: Double) -> CGPoint {
    let angle = Double(index) / Double(values.count) * .pi * 2 - .pi / 2
    return CGPoint(
      x: center.x + cos(angle) * radius * value / 100,
      y: center.y + sin(angle) * radius * value / 100)
  }
  private func polygon(center: CGPoint, radius: Double, values: [Double]) -> Path {
    Path { path in
      for index in values.indices {
        let p = point(index: index, value: values[index], center: center, radius: radius)
        if index == 0 { path.move(to: p) } else { path.addLine(to: p) }
      }
      path.closeSubpath()
    }
  }
}

extension View {
  fileprivate func cardSurface() -> some View {
    modifier(SwiftUIIntelligenceSurface(inset: 6))
  }
  fileprivate func weatherAxes(days: [ForecastDay], yValues: [Double]) -> some View {
    chartXScale(domain: -1...days.count)
      .chartXAxis {
        AxisMarks(values: Array(days.indices)) { axis in
          AxisValueLabel {
            if let index = axis.as(Int.self), days.indices.contains(index) {
              Text(days[index].label).font(.caption2).foregroundStyle(WeatherPalette.muted)
            }
          }
        }
      }
      .chartYAxis {
        AxisMarks(position: .leading, values: yValues) { axis in
          AxisGridLine().foregroundStyle(WeatherPalette.border)
          AxisValueLabel {
            if let value = axis.as(Double.self) {
              Text(value, format: .number.precision(.fractionLength(0)))
                .font(.caption2).foregroundStyle(.primary)
            }
          }
        }
      }
  }
}
