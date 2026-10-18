import Foundation
import SwiftUIIntelligence
@_spi(Testing) @testable import SwiftUIIntelligenceFoundationModels
import Testing

@Suite struct NativeScalarRolesTests {
  private var signature: CalculationRegistry.Signature {
    .init(id: "measure", inputs: ["left": .number, "right": .number, "when": .instant], outputs: [:])
  }

  private func number(_ id: String, value: Double = 2) -> [String: Any] {
    ["id": id, "kind": "number", "value": value, "minimum": -10, "maximum": 100, "step": 0.125]
  }

  private var date: [String: Any] {
    ["id": "date", "kind": "date", "value": "2026-06-01T12:34:56Z"]
  }

  private func encode(_ value: Any) throws -> Data {
    try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
  }

  private func payload(_ inputs: [String: Any], outputs: [String: Any] = [:]) throws -> Data {
    try encode(["declarations": ["measure": ["inputs": inputs, "outputs": outputs]]])
  }

  private func states(_ accepted: AcceptedScalarRoles) throws -> [[String: Any]] {
    try #require(JSONSerialization.jsonObject(with: accepted.stateArrayData) as? [[String: Any]])
  }

  // Given two equal numeric values and a date, when normalized, then complete declarations and distinct roles survive.
  @Test func preservesFullDeclarationsAndEqualValuesWithDifferentIDs() throws {
    let left = number("left", value: 1.2345678901234567)
    let right = number("right", value: 1.2345678901234567)
    let accepted = try NativeScalarRoles.normalizeRoles(payload(["left": left, "right": right, "when": date]), signatures: [signature])
    let declarations = try states(accepted)
    #expect(declarations.count == 3)
    for expected in [left, right, date] {
      let actual = try #require(declarations.first { $0["id"] as? String == expected["id"] as? String })
      #expect(NSDictionary(dictionary: actual).isEqual(to: expected))
    }
    #expect(accepted.roles == ["measure": ["inputs": ["left": "left", "right": "right", "when": "date"], "outputs": [:]]])
  }

  // Given a reference before its full target, when normalized, then only that explicit reference shares the declaration.
  @Test func acceptsForwardReferencesButRejectsDuplicateFullIDsAndInvalidTargets() throws {
    let accepted = try NativeScalarRoles.normalizeRoles(payload(["left": ["reference": "shared"], "right": number("shared"), "when": date]), signatures: [signature])
    #expect(try states(accepted).count == 2)
    #expect(accepted.roles["measure"]?["inputs"]?["left"] == "shared")
    for inputs: [String: Any] in [
      ["left": number("shared"), "right": number("shared"), "when": date],
      ["left": ["reference": "missing"], "right": number("right"), "when": date],
      ["left": ["reference": "date"], "right": number("right"), "when": date],
      ["left": ["reference": "right"], "right": ["reference": "left"], "when": date],
    ] {
      #expect(throws: UIError.self) { try NativeScalarRoles.normalizeRoles(payload(inputs), signatures: [signature]) }
    }
  }

  // Given required slots, when fields are absent, null, unknown, or rely on defaults, then no repair occurs.
  @Test func rejectsIncompleteIncompatibleAndDefaultedDeclarations() throws {
    let valid: [String: Any] = ["left": number("left"), "right": number("right"), "when": date]
    var invalids: [[String: Any]] = []
    for key in ["minimum", "maximum", "step"] {
      var incomplete = number("left"); incomplete.removeValue(forKey: key)
      invalids.append(valid.merging(["left": incomplete]) { _, new in new })
    }
    for replacement: Any in [NSNull(), ["id": "left", "kind": "text", "value": "2"],
      ["reference": "right", "value": 2], number("bad id"), number("left", value: 101)] {
      invalids.append(valid.merging(["left": replacement]) { _, new in new })
    }
    var missing = valid; missing.removeValue(forKey: "right"); invalids.append(missing)
    invalids.append(valid.merging(["extra": number("extra")]) { _, new in new })
    invalids.append(valid.merging(["when": ["id": "date", "kind": "date", "value": "tomorrow"]]) { _, new in new })
    for inputs in invalids {
      #expect(throws: (any Error).self) { try NativeScalarRoles.normalizeRoles(payload(inputs), signatures: [signature]) }
    }
    let text = CalculationRegistry.Signature(id: "measure", inputs: ["left": .text], outputs: [:])
    for declaration: [String: Any] in [
      ["id": "choice", "kind": "choice", "value": "A"],
      ["id": "text", "kind": "text", "value": "A", "minimum": 0],
      ["id": "choice", "kind": "choice", "value": "A", "options": ["B"]],
    ] {
      #expect(throws: (any Error).self) { try NativeScalarRoles.normalizeRoles(payload(["left": declaration]), signatures: [text]) }
    }
  }

  @Test func unicodeScalarLimitsMatchCanonicalStateSchema() throws {
    let textSignature = CalculationRegistry.Signature(id: "measure", inputs: ["text": .text], outputs: [:])
    for (kind, count, limit) in [("text", 2000, 4000), ("choice", 40, 80)] {
      for extra in [0, 1] {
        let value = String(repeating: "e\u{301}", count: count + extra)
        var declaration: [String: Any] = ["id": "source", "kind": kind, "value": value]
        if kind == "choice" { declaration["options"] = [value] }
        let input = try payload(["text": declaration])
        if value.unicodeScalars.count <= limit {
          _ = try NativeScalarRoles.normalizeRoles(input, signatures: [textSignature])
        } else {
          #expect(throws: UIError.self) { try NativeScalarRoles.normalizeRoles(input, signatures: [textSignature]) }
        }
      }
    }
  }

  // Given selected signatures, when schemas are built, then only compatible kinds and exact slots are exposed.
  @Test func schemaIsClosedCompatibleAndSupportsNativeEmptyObjects() throws {
    let selected = CalculationRegistry.Signature(id: "measure", inputs: ["n": .number, "b": .boolean, "t": .text, "d": .instant], outputs: [:])
    let data = try NativeScalarRoles.roleSchema(signatures: [selected])
    let root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    func fields(_ node: [String: Any]) throws -> [String: [String: Any]] {
      #expect(node["additionalProperties"] as? Bool == false)
      let properties = try #require(node["properties"] as? [String: [String: Any]])
      #expect(node["required"] as? [String] == properties.keys.sorted())
      return properties
    }
    let declarations = try fields(try #require(fields(root)["declarations"]))
    #expect(Set(declarations.keys) == ["measure"])
    let directions = try fields(try #require(declarations["measure"]))
    #expect(try fields(try #require(directions["outputs"])).isEmpty)
    let inputs = try fields(try #require(directions["inputs"]))
    for (parameter, expected) in [("n", ["number"]), ("b", ["boolean"]), ("t", ["text", "choice", "date"]), ("d", ["date"])] {
      let variants = try #require(inputs[parameter]?["anyOf"] as? [[String: Any]])
      var kinds: [String] = []
      for variant in variants {
        let properties = try fields(variant)
        if let kind = properties["kind"]?["enum"] as? [String] { kinds += kind }
        else { #expect(Set(properties.keys) == ["reference"]) }
      }
      #expect(Set(kinds) == Set(expected))
    }
    #expect(try FoundationModelsDocumentProvider.validateNativeLayoutSchema(data))
    let restricted = try NativeScalarRoles.roleSchema(signatures: [signature], allowedKinds: [.number, .date])
    #expect(try FoundationModelsDocumentProvider.validateNativeLayoutSchema(restricted))
    #expect(throws: UIError.self) { try NativeScalarRoles.roleSchema(signatures: [signature], allowedKinds: [.number]) }
    let recordOnly = CalculationRegistry.Signature(id: "measure", inputs: [:], outputs: [:], recordInputs: ["rows": .init(fields: ["name": .text])])
    let empty = try NativeScalarRoles.normalizeRoles(payload([:]), signatures: [recordOnly])
    #expect(try states(empty).isEmpty)
    #expect(try FoundationModelsDocumentProvider.validateNativeLayoutSchema(NativeScalarRoles.roleSchema(signatures: [recordOnly])))
  }

  // Given many roles, when 32 full declarations are shared explicitly, then only unique declarations count toward the limit.
  @Test func boundsUniqueDeclarationsNotParameterCountAndPreservesOutputRoles() throws {
    for count in [32, 33] {
      let names = (0..<count).map { "p\($0)" }
      let signature = CalculationRegistry.Signature(id: "measure", inputs: Dictionary(uniqueKeysWithValues: names.map { ($0, .number) }), outputs: ["result": .number])
      let inputs = Dictionary(uniqueKeysWithValues: names.map { ($0, number($0)) })
      let data = try payload(inputs, outputs: ["result": ["reference": "p0"]])
      if count == 32 {
        let accepted = try NativeScalarRoles.normalizeRoles(data, signatures: [signature])
        #expect(try states(accepted).count == 32)
        #expect(accepted.roles["measure"]?["outputs"] == ["result": "p0"])
      } else {
        #expect(throws: UIError.self) { try NativeScalarRoles.normalizeRoles(data, signatures: [signature]) }
      }
    }
  }
}
