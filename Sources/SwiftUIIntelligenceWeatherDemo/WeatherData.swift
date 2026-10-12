import Foundation
import SwiftUIIntelligence

/// A deliberately narrow component for the referenced weather demo, not a chart DSL.
public struct WeatherData: Codable, Sendable {
  public let title: String
  public let subtitle: String
  public let metrics: [WeatherMetric]
  public let days: [ForecastDay]
  public let hours: [ForecastHour]
  public let conditions: [WeatherValue]
  public let wind: [WeatherValue]
  public let summary: String

  enum CodingKeys: String, CodingKey {
    case title, subtitle, metrics, days, hours, conditions, wind, summary
  }
  public init(from decoder: any Decoder) throws {
    try checkKeys(
      decoder,
      allowed: ["title", "subtitle", "metrics", "days", "hours", "conditions", "wind", "summary"])
    let c = try decoder.container(keyedBy: CodingKeys.self)
    title = try c.decode(String.self, forKey: .title)
    subtitle = try c.decode(String.self, forKey: .subtitle)
    metrics = try c.decode([WeatherMetric].self, forKey: .metrics)
    days = try c.decode([ForecastDay].self, forKey: .days)
    hours = try c.decode([ForecastHour].self, forKey: .hours)
    conditions = try c.decode([WeatherValue].self, forKey: .conditions)
    wind = try c.decode([WeatherValue].self, forKey: .wind)
    summary = try c.decode(String.self, forKey: .summary)
    try validate()
  }

  private func validate() throws {
    guard !title.isEmpty, title.count <= 80, subtitle.count <= 120, summary.count <= 1_000 else {
      throw UIError("Invalid weather heading or summary length.")
    }
    try validateItems(metrics.map(\.id), maximum: 6)
    try validateItems(days.map(\.id), maximum: 7)
    try validateItems(hours.map(\.id), maximum: 24)
    try validateItems(conditions.map(\.id), maximum: 8)
    try validateItems(wind.map(\.id), maximum: 8)
    guard
      metrics.allSatisfy({
        !$0.label.isEmpty && $0.label.count <= 24 && $0.value.count <= 16 && $0.detail.count <= 24
      }),
      days.allSatisfy({
        $0.label.count <= 8 && finite($0.high, in: -100...150) && finite($0.low, in: -100...150)
          && $0.low <= $0.high && finite($0.precipitation, in: 0...1_000)
      }),
      hours.allSatisfy({ $0.time.count <= 12 && finite($0.temperature, in: -100...150) }),
      (conditions + wind).allSatisfy({
        !$0.label.isEmpty && $0.label.count <= 20 && finite($0.value, in: 0...100)
      }),
      abs(wind.reduce(0) { $0 + $1.value } - 100) < 0.01
    else {
      throw UIError(
        "Invalid weather data: check labels, numeric ranges and wind percentages (sum 100).")
    }
  }
}

public struct WeatherMetric: Codable, Identifiable, Sendable {
  public let id: String
  public let label: String
  public let value: String
  public let detail: String
  enum CodingKeys: String, CodingKey { case id, label, value, detail }
  public init(from decoder: any Decoder) throws {
    try checkKeys(decoder, allowed: ["id", "label", "value", "detail"])
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decode(String.self, forKey: .id)
    label = try c.decode(String.self, forKey: .label)
    value = try c.decode(String.self, forKey: .value)
    detail = try c.decode(String.self, forKey: .detail)
  }
}

public struct ForecastDay: Codable, Identifiable, Sendable {
  public let id: String
  public let label: String
  public let high: Double
  public let low: Double
  public let precipitation: Double
  enum CodingKeys: String, CodingKey { case id, label, high, low, precipitation }
  public init(from decoder: any Decoder) throws {
    try checkKeys(decoder, allowed: ["id", "label", "high", "low", "precipitation"])
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decode(String.self, forKey: .id)
    label = try c.decode(String.self, forKey: .label)
    high = try c.decode(Double.self, forKey: .high)
    low = try c.decode(Double.self, forKey: .low)
    precipitation = try c.decode(Double.self, forKey: .precipitation)
  }
}

public struct ForecastHour: Codable, Identifiable, Sendable {
  public enum Condition: String, Codable, Sendable {
    case clear = "Clear"
    case partlyCloudy = "Partly Cloudy"
    case mostlySunny = "Mostly Sunny"
    case sunny = "Sunny"
    case cloudy = "Cloudy"
    case lightRain = "Light Rain"
    case rain = "Rain"
    public var symbol: String {
      switch self {
      case .clear, .sunny: "sun.max.fill"
      case .partlyCloudy, .mostlySunny: "cloud.sun.fill"
      case .cloudy: "cloud.fill"
      case .lightRain, .rain: "cloud.rain.fill"
      }
    }
  }
  public let id: String
  public let time: String
  public let condition: Condition
  public let temperature: Double
  enum CodingKeys: String, CodingKey { case id, time, condition, temperature }
  public init(from decoder: any Decoder) throws {
    try checkKeys(decoder, allowed: ["id", "time", "condition", "temperature"])
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decode(String.self, forKey: .id)
    time = try c.decode(String.self, forKey: .time)
    condition = try c.decode(Condition.self, forKey: .condition)
    temperature = try c.decode(Double.self, forKey: .temperature)
  }
}

public struct WeatherValue: Codable, Identifiable, Sendable {
  public let id: String
  public let label: String
  public let value: Double
  enum CodingKeys: String, CodingKey { case id, label, value }
  public init(from decoder: any Decoder) throws {
    try checkKeys(decoder, allowed: ["id", "label", "value"])
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decode(String.self, forKey: .id)
    label = try c.decode(String.self, forKey: .label)
    value = try c.decode(Double.self, forKey: .value)
  }
}

private func finite(_ value: Double, in range: ClosedRange<Double>) -> Bool {
  value.isFinite && range.contains(value)
}

private func validateItems(_ ids: [String], maximum: Int) throws {
  guard !ids.isEmpty, ids.count <= maximum, Set(ids).count == ids.count,
    ids.allSatisfy(validIdentifier)
  else {
    throw UIError("Weather rows need unique stable IDs and 1–\(maximum) items.")
  }
}
