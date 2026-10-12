import Foundation
import SwiftUIIntelligence

public enum WeatherReplayStage: Int, Codable, CaseIterable, Sendable {
  case empty, heading, metrics, temperature, charts, details, finale
}

/// Weather is an opt-in example contract, separate from the generic SDK whitelist.
public struct WeatherDocument: Codable, Sendable {
  public let version: Int
  public let root: Root
  public let floatingActions: [UINode]

  public struct Root: Codable, Sendable {
    public let id: String
    public let type: String
    public let weather: WeatherData
    public var stage: WeatherReplayStage
    enum CodingKeys: String, CodingKey { case id, type, weather, stage }
    public init(from decoder: any Decoder) throws {
      try checkKeys(decoder, allowed: ["id", "type", "weather", "stage"])
      let c = try decoder.container(keyedBy: CodingKeys.self)
      id = try c.decode(String.self, forKey: .id)
      type = try c.decode(String.self, forKey: .type)
      weather = try c.decode(WeatherData.self, forKey: .weather)
      stage = c.contains(.stage) ? try c.decode(WeatherReplayStage.self, forKey: .stage) : .finale
      guard type == "weatherDashboard" else { throw UIError("Expected weatherDashboard root.") }
    }
  }
  enum CodingKeys: String, CodingKey { case version, root, floatingActions }
  public init(from decoder: any Decoder) throws {
    try checkKeys(decoder, allowed: ["version", "root", "floatingActions"])
    let c = try decoder.container(keyedBy: CodingKeys.self)
    version = try c.decode(Int.self, forKey: .version)
    root = try c.decode(Root.self, forKey: .root)
    floatingActions = c.contains(.floatingActions) ? try c.decode([UINode].self, forKey: .floatingActions) : []
  }
  private init(version: Int, root: Root, floatingActions: [UINode]) {
    self.version = version; self.root = root; self.floatingActions = floatingActions
  }

  public static func decode(_ data: Data, registeredActions: Set<String>) throws -> Self {
    guard data.count <= 65_536 else { throw UIError("JSON exceeds the 64 KiB limit.") }
    let document = try JSONDecoder().decode(Self.self, from: data)
    // Reuse core version, ID uniqueness, button bounds and callback whitelist validation.
    struct Envelope: Encodable {
      struct Root: Encodable { let id: String; let type = "vstack"; let children: [UINode] = [] }
      let version: Int
      let root: Root
      let floatingActions: [UINode]
    }
    let envelope = Envelope(version: document.version, root: .init(id: document.root.id), floatingActions: document.floatingActions)
    _ = try UIDocument.decode(JSONEncoder().encode(envelope), registeredActions: registeredActions)
    return document
  }

  public func snapshot(at stage: WeatherReplayStage, registeredActions: Set<String>) throws -> Data {
    var root = root
    root.stage = stage
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(Self(version: version, root: root, floatingActions: floatingActions))
    _ = try Self.decode(data, registeredActions: registeredActions)
    return data
  }
}
