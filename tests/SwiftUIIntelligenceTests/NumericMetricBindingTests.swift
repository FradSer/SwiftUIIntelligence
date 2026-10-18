import Foundation
import Testing
import SwiftUIIntelligence

private let numericMetricJSON = #"{"version":1,"state":[{"id":"amount","kind":"number","value":1654,"minimum":-1000000000,"maximum":1000000000}],"root":{"id":"metric","type":"metric","label":"Amount (minor units)","value":"1654","detail":"Supplied by host","icon":"people","valueBinding":"amount"}}"#

@Test func numericMetricBindingRoundTripsAndRequiresNumericReference() throws {
  // Given a numeric metric, when encoded and decoded, then its reference and static default remain intact.
  let document = try UIDocument.decode(Data(numericMetricJSON.utf8), registeredActions: [])
  let decoded = try UIDocument.decode(JSONEncoder().encode(document), registeredActions: [])
  #expect(decoded.root.valueBinding == "amount")
  #expect(decoded.root.value == "1654")
  for replacement in ["\"missing\"", "null", "42", "true", "{}", "\"bad id\""] {
    let json = numericMetricJSON.replacingOccurrences(of: "\"valueBinding\":\"amount\"", with: "\"valueBinding\":\(replacement)")
    #expect(throws: UIError.self) { try UIDocument.decode(Data(json.utf8), registeredActions: []) }
  }
  for declaration in [#"{"id":"amount","kind":"text","value":"1654"}"#,
    #"{"id":"amount","kind":"boolean","value":true}"#,
    #"{"id":"amount","kind":"choice","value":"1654","options":["1654"]}"#,
    #"{"id":"amount","kind":"date","value":"2026-01-01T00:00:00Z"}"#] {
    var object = try #require(JSONSerialization.jsonObject(with: Data(numericMetricJSON.utf8)) as? [String: Any])
    object["state"] = [try JSONSerialization.jsonObject(with: Data(declaration.utf8))]
    #expect(throws: UIError.self) { try UIDocument.decode(JSONSerialization.data(withJSONObject: object), registeredActions: []) }
  }
}

@Test @MainActor func numericMetricEditsPreserveIntegerAndFractionDigits() throws {
  // Given bound numeric state, when edited, then the resolver uses all Double digits without changing the default.
  let document = try UIDocument.decode(Data(numericMetricJSON.utf8), registeredActions: [])
  let state = DocumentState()
  state.load(document)
  #expect(try document.root.resolvedMetricValue(values: state.values) == "1654")
  try state.set("amount", to: .number(1658))
  #expect(try document.root.resolvedMetricValue(values: state.values) == "1658")
  try state.set("amount", to: .number(16.58123456789))
  #expect(try document.root.resolvedMetricValue(values: state.values) == "16.58123456789")
  #expect(document.root.value == "1654")
  for invalid: Double in [.nan, .infinity, -.infinity, 1_000_000_001, -1_000_000_001] {
    #expect(throws: UIError.self) { try state.set("amount", to: .number(invalid)) }
    #expect(throws: UIError.self) { try document.root.resolvedMetricValue(values: ["amount": .number(invalid)]) }
  }
  #expect(state.values["amount"] == .number(16.58123456789))
  for invalid: [String: StateValue] in [[:], ["amount": .text("1658")], ["amount": .boolean(true)]] {
    #expect(throws: UIError.self) { try document.root.resolvedMetricValue(values: invalid) }
  }
}

@Test func staticMetricLegacyJSONRemainsUnchanged() throws {
  // Given old JSON without a binding, when resolved or round-tripped, then the exact static text remains.
  let json = numericMetricJSON.replacingOccurrences(of: ",\"valueBinding\":\"amount\"", with: "")
    .replacingOccurrences(of: "\"value\":\"1654\"", with: "\"value\":\"16.54 supplied units\"")
  let document = try UIDocument.decode(Data(json.utf8), registeredActions: [])
  #expect(document.root.valueBinding == nil)
  #expect(try document.root.resolvedMetricValue(values: ["amount": .number(1658)]) == "16.54 supplied units")
  let encoded = try JSONEncoder().encode(document)
  let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
  let root = try #require(object["root"] as? [String: Any])
  #expect(root["valueBinding"] == nil)
  #expect(try UIDocument.decode(encoded, registeredActions: []).root.value == document.root.value)
}

@Test func numericMetricBindingDoesNotRelaxRequiredDefaultsOrOtherNodeFields() throws {
  // Given a binding, when the static default is missing/invalid or the property belongs to another kind, then decoding fails.
  for json in [numericMetricJSON.replacingOccurrences(of: "\"value\":\"1654\",", with: ""),
    numericMetricJSON.replacingOccurrences(of: "\"value\":\"1654\"", with: "\"value\":\"\""),
    numericMetricJSON.replacingOccurrences(of: "\"value\":\"1654\"", with: "\"value\":null"),
    numericMetricJSON.replacingOccurrences(of: "\"valueBinding\"", with: "\"unknownBinding\""),
    #"{"version":1,"root":{"id":"t","type":"text","text":"Static","valueBinding":"amount"}}"#] {
    #expect(throws: UIError.self) { try UIDocument.decode(Data(json.utf8), registeredActions: []) }
  }
}

@Test func numericMetricSchemaKeepsBindingOptionalAndDefaultRequired() throws {
  // Given canonical and compact schemas, when metric is selected, then only the numeric reference is optional.
  for components: Set<String>? in [nil, ["metric"]] {
    let schema = try #require(JSONSerialization.jsonObject(with: DocumentGenerationContract.schemaJSON(componentTypes: components)) as? [String: Any])
    let definitions = try #require(schema["$defs"] as? [String: [String: Any]])
    let metric = try #require(definitions["metric"])
    let properties = try #require(metric["properties"] as? [String: [String: Any]])
    let binding = try #require(properties["valueBinding"])
    #expect(binding["type"] as? String == "string")
    let required = try #require(metric["required"] as? [String])
    #expect(required.contains("value"))
    #expect(!required.contains("valueBinding"))
  }
}
