import Foundation
import Testing

@testable import SwiftUIIntelligence
import SwiftUIIntelligenceWeatherDemo

private func weatherFixture() throws -> Data {
  let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent()
  return try Data(contentsOf: root.appendingPathComponent("Example/SwiftUIIntelligenceDemo/sample.json"))
}

@Test func weatherFixtureAndEveryReplayStageAreValidated() throws {
  let names: Set<String> = ["replay", "pause", "complete"]
  let original = try WeatherDocument.decode(weatherFixture(), registeredActions: names)
  for stage in WeatherReplayStage.allCases {
    let data = try original.snapshot(at: stage, registeredActions: names)
    let document = try WeatherDocument.decode(data, registeredActions: names)
    #expect(document.root.type == "weatherDashboard")
    #expect(document.root.stage == stage)
    #expect(document.root.weather.metrics.count == 6)
    #expect(document.root.weather.wind.map(\.value) == [38, 25, 18, 12, 7])
    #expect(document.root.id == "weather-demo")
  }
}

@Test(arguments: [
  "extra-field", "unknown-condition", "duplicate-metric", "bad-percentage", "bad-range",
  "bad-stage", "oversized-array", "unknown-action", "nested-dashboard",
])
func invalidWeatherInputIsRejected(change: String) throws {
  var json = try #require(JSONSerialization.jsonObject(with: weatherFixture()) as? [String: Any])
  var root = try #require(json["root"] as? [String: Any])
  var weather = try #require(root["weather"] as? [String: Any])
  switch change {
  case "extra-field": weather["script"] = "arbitrary code"
  case "unknown-condition":
    var hours = try #require(weather["hours"] as? [[String: Any]])
    hours[0]["condition"] = "exec"
    weather["hours"] = hours
  case "duplicate-metric":
    var metrics = try #require(weather["metrics"] as? [[String: Any]])
    metrics[1]["id"] = metrics[0]["id"]
    weather["metrics"] = metrics
  case "bad-percentage":
    var wind = try #require(weather["wind"] as? [[String: Any]])
    wind[0]["value"] = 99
    weather["wind"] = wind
  case "bad-range":
    var days = try #require(weather["days"] as? [[String: Any]])
    days[0]["low"] = 200
    weather["days"] = days
  case "bad-stage": root["stage"] = 7
  case "oversized-array":
    let rows = try #require(weather["days"] as? [[String: Any]])
    weather["days"] = Array(repeating: rows[0], count: 100)
  case "unknown-action":
    json["floatingActions"] = [
      ["id": "unsafe", "type": "button", "title": "Run", "action": "shell"]
    ]
  default: break
  }
  root["weather"] = weather
  json["root"] = root
  if change == "nested-dashboard" {
    json["root"] = ["id": "wrapper", "type": "vstack", "children": [root]]
  }
  let data = try JSONSerialization.data(withJSONObject: json)
  #expect(throws: (any Error).self) {
    try WeatherDocument.decode(data, registeredActions: ["replay", "pause", "complete"])
  }
}

@Test func coreRejectsWeatherDemoContract() throws {
  #expect(throws: UIError.self) {
    try UIDocument.decode(weatherFixture(), registeredActions: ["replay", "pause", "complete"])
  }
}

@Test func replayDoesNotDependOnJSONWhitespace() throws {
  let names: Set<String> = ["replay", "pause", "complete"]
  let compact = try JSONSerialization.data(withJSONObject: JSONSerialization.jsonObject(with: weatherFixture()))
  let document = try WeatherDocument.decode(compact, registeredActions: names)
  let empty = try document.snapshot(at: .empty, registeredActions: names)
  #expect(try WeatherDocument.decode(empty, registeredActions: names).root.stage == .empty)
}

@Test(arguments: ["null-stage", "extra-root", "duplicate-action-id", "wrong-version"])
func demoEnvelopeValidationIsPreserved(change: String) throws {
  var json = try #require(JSONSerialization.jsonObject(with: weatherFixture()) as? [String: Any])
  var root = try #require(json["root"] as? [String: Any])
  switch change {
  case "null-stage": root["stage"] = NSNull()
  case "extra-root": root["code"] = "arbitrary code"
  case "duplicate-action-id":
    var buttons = try #require(json["floatingActions"] as? [[String: Any]])
    buttons[0]["id"] = root["id"]
    json["floatingActions"] = buttons
  case "wrong-version": json["version"] = 2
  default: break
  }
  json["root"] = root
  let data = try JSONSerialization.data(withJSONObject: json)
  #expect(throws: (any Error).self) {
    try WeatherDocument.decode(data, registeredActions: ["replay", "pause", "complete"])
  }
}
