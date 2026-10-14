import Foundation
#if canImport(AppKit)
import AppKit
#endif
import FoundationModels
import SwiftUIIntelligenceFoundationModels
import SwiftUIIntelligenceWeatherDemo
import Testing
@testable import SwiftUIIntelligence

private func decodeNode(_ node: String) throws -> UIDocument {
  try UIDocument.decode(Data("{\"version\":1,\"root\":\(node)}".utf8), registeredActions: [])
}

@Test func semanticSymbolCatalogAndUnknownFallback() throws {
  #expect(SymbolCatalog.keys.count >= 60)
  #if canImport(AppKit)
  for symbol in SymbolCatalog.symbols.values { #expect(NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil, "Unavailable SF Symbol: \(symbol)") }
  #endif
  #expect(Set(SymbolCatalog.keys).count == SymbolCatalog.keys.count)
  #expect(SymbolCatalog.systemName(for: "rain") == "cloud.rain.fill")
  #expect(SymbolCatalog.systemName(for: "unsupported-symbol") == "questionmark.circle")
  let document = try decodeNode(#"{"id":"m","type":"metric","label":"Count","value":"3","detail":"Synthetic","icon":"unsupported-symbol"}"#)
  #expect(document.root.icon == "unsupported-symbol")
  #expect(try UIDocument.decode(DocumentGenerationContract.canonicalJSON(document), registeredActions: []).root.icon == "unsupported-symbol")
}

@Test(arguments: [
  #"{"id":"m","type":"metric","label":"Count","value":"3","detail":"Synthetic","icon":"people"}"#,
  #"{"id":"g","type":"grid","columnCount":3,"children":[],"spacing":8}"#,
  #"{"id":"i","type":"iconList","iconItems":[{"text":"Review","icon":"checklist"}]}"#,
  #"{"id":"b","type":"badge","text":"Ready","tone":"success","icon":"success"}"#,
  #"{"id":"p","type":"progress","title":"Review","completed":3,"total":5,"icon":"task"}"#,
  #"{"id":"c","type":"chart","title":"Weekly count","chartStyle":"line","points":[{"label":"Mon","value":3,"series":"A"},{"label":"Tue","value":5,"series":"A"}]}"#,
  #"{"id":"d","type":"chart","title":"Share","chartStyle":"donut","points":[{"label":"A","value":3,"series":"Share"}]}"#,
  #"{"id":"r","type":"chart","title":"Scores","chartStyle":"radar","points":[{"label":"A","value":3,"series":"Score"},{"label":"B","value":70,"series":"Score"},{"label":"C","value":100,"series":"Score"}]}"#,
]) func richNodesRoundTrip(node: String) throws {
  let document = try decodeNode(node)
  let json = try DocumentGenerationContract.canonicalJSON(document)
  let second = try UIDocument.decode(json, registeredActions: [])
  #expect(second.root.type == document.root.type)
}

@Test(arguments: [
  #"{"id":"m","type":"metric","label":"Count","value":"3","detail":"Synthetic"}"#,
  #"{"id":"g","type":"grid","columnCount":7,"children":[],"spacing":8}"#,
  #"{"id":"i","type":"iconList","iconItems":[{"text":"Review","icon":"https://example.com"}]}"#,
  #"{"id":"i","type":"iconList","iconItems":[{"text":"Review","icon":"task","url":"bad"}]}"#,
  #"{"id":"b","type":"badge","text":"Ready","tone":"unsafe"}"#,
  #"{"id":"p","type":"progress","title":"Review","completed":6,"total":5,"icon":"task"}"#,
  #"{"id":"p","type":"progress","title":"Review","completed":0,"total":0,"icon":"task"}"#,
  #"{"id":"d","type":"chart","title":"Share","chartStyle":"donut","points":[{"label":"A","value":-3,"series":"Share"}]}"#,
  #"{"id":"c","type":"chart","title":"Trend","chartStyle":"line","points":[{"label":"A","value":3,"series":"Count"},{"label":"A","value":4,"series":"Count"}]}"#,
  #"{"id":"r","type":"chart","title":"Scores","chartStyle":"radar","points":[{"label":"A","value":101,"series":"Score"},{"label":"B","value":70,"series":"Score"},{"label":"C","value":100,"series":"Score"}]}"#,
]) func invalidRichContentIsRejected(node: String) {
  #expect(throws: UIError.self) { try decodeNode(node) }
}

@Test func compactGenerationSchemaRetainsRequiredComponentsAndIconCatalog() throws {
  let subset: Set<String> = ["metric", "chart", "badge"]
  let schema = try JSONSerialization.jsonObject(with: DocumentGenerationContract.schemaJSON(componentTypes: subset)) as! [String: Any]
  let defs = schema["$defs"] as! [String: [String: Any]]
  #expect(defs["metric"] != nil && defs["chart"] != nil && defs["table"] == nil)
  #expect((defs["Icon"]?["enum"] as? [String]) == SymbolCatalog.keys)
  let request = try DocumentGenerationRequest(messages: [.init(role: .user, content: "Synthetic statistics")])
  let full = try JSONEncoder().encode(FoundationModelsDocumentProvider.generationSchema(for: request))
  let small = try JSONEncoder().encode(FoundationModelsDocumentProvider.generationSchema(for: request, componentTypes: subset))
  #expect(small.count < full.count)
}

@Test func completeWeatherReferenceUsesGenericComponentsAtEveryStage() throws {
  let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  let data = try Data(contentsOf: root.appendingPathComponent("Example/SwiftUIIntelligenceDemo/sample.json"))
  let names: Set<String> = ["replay", "pause", "complete"]
  let original = try WeatherDocument.decode(data, registeredActions: names)
  for stage in WeatherReplayStage.allCases {
    let weather = try WeatherDocument.decode(original.snapshot(at: stage, registeredActions: names), registeredActions: names)
    let document = try GenericWeatherReference.document(from: weather, registeredActions: names)
    let encoded = try DocumentGenerationContract.canonicalJSON(document)
    #expect(!String(decoding: encoded, as: UTF8.self).contains("weatherDashboard"))
    if stage == .finale {
      var nodes: [UINode] = []
      func walk(_ node: UINode) { nodes.append(node); node.children.forEach(walk) }
      walk(document.root)
      #expect(nodes.filter { $0.type == .metric }.count == 6)
      #expect(nodes.filter { $0.type == .chart }.map(\.chartStyle) == [.line, .area, .radar, .donut])
      #expect(nodes.first { $0.id == "temperature-chart" }?.points.count == 14)
      #expect(nodes.first { $0.id == "forecast-summary-text" }?.text == weather.root.weather.summary)
      #expect(nodes.filter { $0.id.hasSuffix("-condition") }.count == 7)
    }
  }
}

@Test func groupedSectionSuppressesNestedLayoutSurfaces() {
  #expect(!DocumentSurfacePolicy.childSurface(parentShowsSurface: false))
}

@Test func documentContractPrefersNarrativeWithoutForcingDashboards() {
  let instructions = DocumentGenerationContract.instructions(registeredActions: [])
  #expect(instructions.contains("Lead with an answer paragraph"))
  #expect(instructions.contains("Only use a dashboard when the user requests one"))
}

@Test func ungroupedLayoutsRetainChildGlassSurfaces() {
  #expect(DocumentSurfacePolicy.childSurface(parentShowsSurface: true))
}

@Test func cardPaletteRoundTripsAndPreservesOldJSON() throws {
  let colored = try decodeNode(#"{"id":"s","type":"section","title":"Events","spacing":12,"cardColor":"blue","children":[{"id":"t","type":"timeline","title":"Dates","events":[{"time":"April 1","title":"Birthday","detail":"All-day","cardColor":"orange"}]}]}"#)
  let json = String(decoding: try DocumentGenerationContract.canonicalJSON(colored), as: UTF8.self)
  #expect(json.contains("\"cardColor\" : \"blue\""))
  #expect(json.contains("\"cardColor\" : \"orange\""))
  let old = try decodeNode(#"{"id":"t","type":"text","text":"Original","style":"body"}"#)
  #expect(!String(decoding: try DocumentGenerationContract.canonicalJSON(old), as: UTF8.self).contains("cardColor"))
}

@Test(arguments: ["red", "#ff8800", "https://example.com"]) func unknownCardColorsAreRejected(color: String) {
  #expect(throws: (any Error).self) { try decodeNode("{\"id\":\"t\",\"type\":\"text\",\"text\":\"Test\",\"style\":\"body\",\"cardColor\":\"\(color)\"}") }
}

@Test(arguments: [
  #"{"id":"t","type":"text","text":"Test","style":"body","cardColor":null}"#,
  #"{"id":"t","type":"timeline","title":"Dates","events":[{"time":"April 1","title":"Birthday","detail":"All-day","cardColor":null}]}"#,
]) func explicitNullCardColorsAreRejected(node: String) {
  #expect(throws: (any Error).self) { try decodeNode(node) }
}
