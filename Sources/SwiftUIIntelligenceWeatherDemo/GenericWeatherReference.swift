import Foundation
import SwiftUIIntelligence

/// The complete reference dataset expressed through business-independent SDK components.
/// The replay host owns stage/timing/actions; this adapter performs no model inference.
public enum GenericWeatherReference {
  public static func document(from source: WeatherDocument, registeredActions: Set<String>) throws -> UIDocument {
    let weather = source.root.weather
    let stage = source.root.stage
    var children: [ReferenceNode] = []
    if stage == .empty {
      children = [.text("empty-reference", "Rendered UI will appear here", icon: "computer")]
    } else {
      var header = ReferenceNode(id: "weather-heading", type: "hstack")
      header.spacing = 12
      var live = ReferenceNode(id: "live-status", type: "badge")
      live.text = "Live"; live.tone = "note"; live.icon = "refresh"
      header.children = [.text("weather-title", weather.title, style: "headline", icon: "partlyCloudy"), .text("weather-subtitle", weather.subtitle, style: "caption"), live]
      children.append(header)
      if stage.rawValue >= 2 {
        let icons = ["temperature", "temperature", "humidity", "wind", "sun", "visibility"]
        let metrics = weather.metrics.enumerated().map { index, metric in
          var node = ReferenceNode(id: metric.id, type: "metric")
          node.label = metric.label; node.value = metric.value; node.detail = metric.detail
          node.icon = icons[index % icons.count]; return node
        }
        var group = ReferenceNode(id: "reference-metrics", type: "grid")
        group.columnCount = 6; group.children = metrics; group.spacing = 8; children.append(group)
      }
      if stage.rawValue >= 3 {
        let temperatures = weather.days.flatMap { day in
          [ReferencePoint(label: day.label, value: day.high, series: "High"), ReferencePoint(label: day.label, value: day.low, series: "Low")]
        }
        let temperature = ReferenceNode.chart("temperature-chart", "7-Day Temperature Forecast", "line", temperatures)
        if stage.rawValue >= 4 {
          let precipitation = ReferenceNode.chart("precipitation-chart", "Precipitation (mm)", "area", weather.days.map { .init(label: $0.label, value: $0.precipitation, series: "Precipitation") })
          var group = ReferenceNode(id: "reference-charts", type: "hstack")
          group.children = [temperature, precipitation]; group.spacing = 8; children.append(group)
        } else { children.append(temperature) }
      }
      if stage.rawValue >= 5 {
        var hours = ReferenceNode(id: "hourly-forecast", type: "section")
        hours.title = "Hourly Forecast"; hours.icon = "time"; hours.spacing = 12
        var rows: [ReferenceNode] = []
        var columns = ReferenceNode(id: "hourly-header", type: "hstack")
        columns.children = [.text("time-column", "Time", style: "caption"), .text("condition-column", "Condition", style: "caption"), .text("degree-column", "°F", style: "caption")]
        columns.spacing = 8; rows.append(columns)
        for hour in weather.hours {
          var row = ReferenceNode(id: hour.id, type: "hstack")
          let icon: String = switch hour.condition {
          case .clear, .sunny: "sun"
          case .mostlySunny, .partlyCloudy: "partlyCloudy"
          case .cloudy: "cloud"
          case .lightRain, .rain: "rain"
          }
          row.children = [.text(hour.id + "-time", hour.time, style: "caption"), .text(hour.id + "-condition", hour.condition.rawValue, style: "caption", icon: icon), .text(hour.id + "-temperature", String(Int(hour.temperature)), style: "caption")]
          row.spacing = 8; rows.append(row)
        }
        hours.children = rows
        let radar = ReferenceNode.chart("conditions-breakdown", "Conditions Breakdown", "radar", weather.conditions.map { .init(label: $0.label, value: $0.value, series: "Today") })
        let donut = ReferenceNode.chart("wind-distribution", "Wind Distribution", "donut", weather.wind.map { .init(label: $0.label, value: $0.value, series: "Wind %") })
        var summary = ReferenceNode(id: "forecast-summary", type: "section")
        summary.title = "Forecast Summary"; summary.spacing = 8
        summary.children = [.text("forecast-summary-text", weather.summary, style: "caption")]
        var wind = ReferenceNode(id: "wind-reference", type: "section")
        wind.title = "Wind & forecast"; wind.icon = "wind"; wind.spacing = 12; wind.children = [donut, summary]
        var details = ReferenceNode(id: "weather-details", type: "hstack")
        details.children = [hours, radar, wind]; details.spacing = 8; children.append(details)
      }
    }
    var root = ReferenceNode(id: source.root.id, type: "vstack")
    root.children = children; root.spacing = 8
    let data = try JSONEncoder().encode(ReferenceDocument(root: root))
    return try UIDocument.decode(data, registeredActions: registeredActions)
  }
}

private struct ReferenceDocument: Encodable {
  let version = 1
  let root: ReferenceNode
  let floatingActions: [UINode] = []
}
private struct ReferencePoint: Encodable { let label: String; let value: Double; let series: String }
private struct ReferenceNode: Encodable {
  let id: String
  let type: String
  var children: [ReferenceNode]?
  var spacing: Double?
  var columnCount: Int?
  var text: String?
  var style: String?
  var title: String?
  var icon: String?
  var tone: String?
  var label: String?
  var value: String?
  var detail: String?
  var chartStyle: String?
  var points: [ReferencePoint]?
  static func text(_ id: String, _ text: String, style: String = "body", icon: String? = nil) -> Self {
    var node = Self(id: id, type: "text"); node.text = text; node.style = style; node.icon = icon; return node
  }
  static func chart(_ id: String, _ title: String, _ style: String, _ points: [ReferencePoint]) -> Self {
    var node = Self(id: id, type: "chart"); node.title = title; node.chartStyle = style; node.points = points; return node
  }
}
