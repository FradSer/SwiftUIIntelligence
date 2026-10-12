import Foundation

/// Versioned semantic SF Symbols catalog. JSON never names arbitrary image assets or URLs.
public enum SymbolCatalog {
  public static let symbols: [String: String] = [
    "info": "info.circle", "warning": "exclamationmark.triangle", "success": "checkmark.circle",
    "pending": "clock", "error": "xmark.circle", "help": "questionmark.circle",
    "calendar": "calendar", "time": "clock", "location": "location", "map": "map",
    "person": "person", "people": "person.2", "book": "book", "document": "doc.text",
    "folder": "folder", "checklist": "checklist", "task": "checkmark.square", "note": "note.text",
    "message": "bubble.left", "mail": "envelope", "phone": "phone", "link": "link",
    "download": "arrow.down.circle", "upload": "arrow.up.circle", "refresh": "arrow.clockwise",
    "save": "square.and.arrow.down", "share": "square.and.arrow.up", "search": "magnifyingglass",
    "settings": "gearshape", "lock": "lock", "shield": "shield", "key": "key",
    "computer": "desktopcomputer", "device": "iphone", "network": "network", "storage": "externaldrive",
    "code": "chevron.left.forwardslash.chevron.right", "release": "shippingbox", "flag": "flag",
    "chart": "chart.xyaxis.line", "trendUp": "arrow.up.right", "trendDown": "arrow.down.right",
    "money": "banknote", "cart": "cart", "heart": "heart", "energy": "bolt",
    "sun": "sun.max.fill", "cloud": "cloud.fill", "partlyCloudy": "cloud.sun.fill",
    "rain": "cloud.rain.fill", "snow": "cloud.snow.fill", "storm": "cloud.bolt.rain.fill",
    "temperature": "thermometer.medium", "humidity": "humidity.fill", "wind": "wind",
    "pressure": "gauge.medium", "visibility": "eye", "drop": "drop.fill", "moon": "moon.fill",
    "leaf": "leaf", "travel": "airplane", "home": "house", "star": "star", "play": "play.circle",
  ]
  public static var keys: [String] { symbols.keys.sorted() }
  public static func systemName(for key: String) -> String { symbols[key] ?? "questionmark.circle" }
  public static func isKnown(_ key: String) -> Bool { symbols[key] != nil }
}

public struct IconItem: Codable, Sendable {
  public let text: String
  public let icon: String
  public init(from decoder: any Decoder) throws {
    try checkKeys(decoder, allowed: ["text", "icon"])
    let c = try decoder.container(keyedBy: CodingKeys.self)
    text = try c.decode(String.self, forKey: .text)
    icon = try c.decode(String.self, forKey: .icon)
  }
  private enum CodingKeys: String, CodingKey { case text, icon }
}

public struct ChartPoint: Codable, Sendable {
  public let label: String
  public let value: Double
  public let series: String
  public init(from decoder: any Decoder) throws {
    try checkKeys(decoder, allowed: ["label", "value", "series"])
    let c = try decoder.container(keyedBy: CodingKeys.self)
    label = try c.decode(String.self, forKey: .label)
    value = try c.decode(Double.self, forKey: .value)
    series = try c.decode(String.self, forKey: .series)
  }
  private enum CodingKeys: String, CodingKey { case label, value, series }
}
