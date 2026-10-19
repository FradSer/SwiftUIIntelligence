import Foundation
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif

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
    "sliders": "slider.horizontal.3", "filter": "line.3.horizontal.decrease.circle",
    "tune": "slider.horizontal.3", "barChart": "chart.bar.fill", "ruler": "ruler",
    "scale": "scalemass", "tag": "tag", "price": "tag", "weight": "scalemass",
    "food": "fork.knife", "meal": "fork.knife", "drink": "cup.and.saucer", "receipt": "receipt",
    "timer": "timer", "stopwatch": "stopwatch",
    "wifi": "wifi", "bed": "bed.double.fill", "hotel": "building.2.fill", "spa": "water.waves",
    "waves": "water.waves", "favorite": "heart.fill", "photo": "photo.fill", "gallery": "photo.stack",
    "family": "figure.2.and.child.holdinghands",
  ]
  public static var keys: [String] { symbols.keys.sorted() }
  public static func systemName(for key: String) -> String {
    if let mapped = symbols[key] { return mapped }
    #if canImport(UIKit)
    if UIKit.UIImage(systemName: key) != nil { return key }
    #elseif canImport(AppKit)
    if AppKit.NSImage(systemSymbolName: key, accessibilityDescription: nil) != nil { return key }
    #endif
    return "questionmark.circle"
  }
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
  public let binding: String?
  public let label: String
  public let value: Double
  public let series: String
  public init(from decoder: any Decoder) throws {
    try checkKeys(decoder, allowed: ["label", "value", "series", "binding"])
    let c = try decoder.container(keyedBy: CodingKeys.self)
    binding = c.contains(.binding) ? try c.decode(String.self, forKey: .binding) : nil
    label = try c.decode(String.self, forKey: .label)
    value = try c.decode(Double.self, forKey: .value)
    series = try c.decode(String.self, forKey: .series)
  }
  func resolved(in state: [String: StateValue]) throws -> ChartPoint {
    ChartPoint(label: label, value: try resolvedValue(in: state), series: series)
  }

  init(label: String, value: Double, series: String) {
    self.label = label
    self.value = value
    self.series = series
    self.binding = nil
  }

  public func resolvedValue(in state: [String: StateValue]) throws -> Double {
    guard let binding else { return value }
    guard case .number(let number) = state[binding], number.isFinite, abs(number) <= 1e9 else {
      throw UIError("Chart point requires a finite numeric state value.")
    }
    return number
  }

  private enum CodingKeys: String, CodingKey { case label, value, series, binding }
}
