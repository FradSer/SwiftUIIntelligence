import Foundation
import SwiftUIIntelligence
@_spi(Testing) @testable import SwiftUIIntelligenceFoundationModels
import Testing

@Suite struct NativeNumberConstraintTests {
  private func encode(_ value: Any) throws -> Data {
    try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
  }

  private func signature(_ constraints: [String: Any] = ["count": ["minimum": 1, "maximum": 10, "integer": true, "step": 1]],
    inputs: [String: String] = ["count": "number", "other": "number"]) throws -> CalculationRegistry.Signature {
    try JSONDecoder().decode(CalculationRegistry.Signature.self, from: encode([
      "id": "measure", "inputs": inputs, "outputs": ["result": "number"], "inputNumberConstraints": constraints,
    ]))
  }

  private func number(_ id: String, value: Double = 3, minimum: Double = 1,
    maximum: Double = 10, step: Double = 1) -> [String: Any] {
    ["id": id, "kind": "number", "value": value, "minimum": minimum, "maximum": maximum, "step": step]
  }

  private func payload(_ count: [String: Any], other: [String: Any]? = nil,
    output: [String: Any]? = nil) throws -> Data {
    try encode(["declarations": ["measure": [
      "inputs": ["count": count, "other": other ?? number("other", value: -2.5, minimum: -100, maximum: 100, step: 0.5)],
      "outputs": ["result": output ?? number("result", value: 99.5, minimum: -100, maximum: 100, step: 0.5)],
    ]]])
  }

  private func properties(_ node: [String: Any]) throws -> [String: [String: Any]] {
    try #require(node["properties"] as? [String: [String: Any]])
  }

  private func slots(_ data: Data) throws -> (inputs: [String: [String: Any]], outputs: [String: [String: Any]]) {
    let root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let declarations = try properties(try #require(properties(root)["declarations"]))
    let directions = try properties(try #require(declarations["measure"]))
    return (try properties(try #require(directions["inputs"])), try properties(try #require(directions["outputs"])))
  }

  // Given constrained inputs, when guidance is built, then all three numeric domains narrow and references stay intact.
  @Test func schemaNarrowsOnlyConstrainedInputDeclarations() throws {
    let constrained = try NativeScalarRoles.roleSchema(signatures: [signature()])
    let baseline = try NativeScalarRoles.roleSchema(signatures: [signature([:])])
    let actual = try slots(constrained)
    let original = try slots(baseline)
    #expect(NSDictionary(dictionary: actual.outputs).isEqual(to: original.outputs))
    #expect(NSDictionary(dictionary: try #require(actual.inputs["other"])).isEqual(to: try #require(original.inputs["other"])))
    let variants = try #require(actual.inputs["count"]?["anyOf"] as? [[String: Any]])
    let originalVariants = try #require(original.inputs["count"]?["anyOf"] as? [[String: Any]])
    #expect(variants.count == 2)
    #expect(NSDictionary(dictionary: variants[1]).isEqual(to: originalVariants[1]))
    let numeric = try properties(variants[0])
    for name in ["value", "minimum", "maximum"] {
      #expect(numeric[name]?["type"] as? String == "integer")
      #expect(numeric[name]?["minimum"] as? Double == 1)
      #expect(numeric[name]?["maximum"] as? Double == 10)
    }
    #expect(numeric["step"]?["type"] as? String == "number")
    #expect(numeric["step"]?["enum"] as? [Double] == [1])
    #expect(numeric["step"]?["minimum"] as? Double == 1)
    #expect(numeric["step"]?["maximum"] as? Double == 1)
    #expect(try FoundationModelsDocumentProvider.validateNativeLayoutSchema(constrained))
  }

  @Test func integerDomainWithoutFixedStepGuidesPositiveIntegerSteps() throws {
    let data = try NativeScalarRoles.roleSchema(signatures: [signature(["count": ["minimum": 1, "maximum": 10, "integer": true]])])
    let variants = try #require(slots(data).inputs["count"]?["anyOf"] as? [[String: Any]])
    let fields = try properties(variants[0])
    #expect(fields["step"]?["type"] as? String == "integer")
    #expect(fields["step"]?["minimum"] as? Double == 1)
    #expect(fields["step"]?["maximum"] as? Double == 1e9)
    #expect(fields["step"]?["enum"] == nil)
    #expect(try FoundationModelsDocumentProvider.validateNativeLayoutSchema(data))
  }

  // Given fractional metadata without a required step, when guided, then number types and canonical step bounds survive.
  @Test func fractionalGuidanceAndOptionalStep() throws {
    let data = try NativeScalarRoles.roleSchema(signatures: [signature(["count": ["minimum": -2.5, "maximum": 7.25]])])
    let variants = try #require(slots(data).inputs["count"]?["anyOf"] as? [[String: Any]])
    let numeric = try properties(variants[0])
    for name in ["value", "minimum", "maximum"] {
      #expect(numeric[name]?["type"] as? String == "number")
      #expect(numeric[name]?["minimum"] as? Double == -2.5)
      #expect(numeric[name]?["maximum"] as? Double == 7.25)
    }
    #expect(numeric["step"]?["enum"] == nil)
    #expect(numeric["step"]?["exclusiveMinimum"] as? Double == 0)
    #expect(try FoundationModelsDocumentProvider.validateNativeLayoutSchema(data))
  }

  // Given valid narrower authored bounds, when normalized, then declarations retain their exact JSON values and IDs.
  @Test func narrowerDeclarationsArePreservedWithoutDefaultsOrDeduplication() throws {
    let count = number("count", value: 4, minimum: 2, maximum: 8)
    let other = number("other", value: 4, minimum: -100, maximum: 100, step: 0.25)
    let accepted = try NativeScalarRoles.normalizeRoles(payload(count, other: other), signatures: [signature()])
    let declarations = try #require(JSONSerialization.jsonObject(with: accepted.stateArrayData) as? [[String: Any]])
    #expect(declarations.count == 3)
    for expected in [count, other] {
      let actual = try #require(declarations.first { $0["id"] as? String == expected["id"] as? String })
      #expect(try encode(actual) == encode(expected))
    }
    #expect(accepted.roles["measure"]?["inputs"] == ["count": "count", "other": "other"])
  }

  // Given a numeric input, when any authored domain exceeds authority, then reject rather than clamp or repair it.
  @Test func rejectsInvalidFullDeclarations() throws {
    let selected = try signature()
    for invalid in [
      number("count", minimum: 0), number("count", maximum: 11),
      number("count", value: 3.5), number("count", minimum: 1.5),
      number("count", maximum: 9.5), number("count", step: 0.5),
      number("count", value: 0), number("count", value: 11),
    ] {
      #expect(throws: (any Error).self) { try NativeScalarRoles.normalizeRoles(payload(invalid), signatures: [selected]) }
    }
    for key in ["minimum", "maximum", "step", "value"] {
      var invalid = number("count")
      invalid.removeValue(forKey: key)
      #expect(throws: (any Error).self) { try NativeScalarRoles.normalizeRoles(payload(invalid), signatures: [selected]) }
      invalid[key] = NSNull()
      #expect(throws: (any Error).self) { try NativeScalarRoles.normalizeRoles(payload(invalid), signatures: [selected]) }
    }
  }

  // Given explicit forward references, when consumed by a constrained input, then validate the resolved field, not the reference object.
  @Test func validatesForwardReferencesIncludingOutputDeclarations() throws {
    let selected = try signature()
    for target in ["other", "result"] {
      let good = number(target, value: 4, minimum: 2, maximum: 8)
      let accepted = try NativeScalarRoles.normalizeRoles(payload(["reference": target], other: target == "other" ? good : nil,
        output: target == "result" ? good : nil), signatures: [selected])
      #expect(accepted.roles["measure"]?["inputs"]?["count"] == target)
      let bad = number(target, value: 4, minimum: 0, maximum: 100)
      #expect(throws: (any Error).self) {
        try NativeScalarRoles.normalizeRoles(payload(["reference": target], other: target == "other" ? bad : nil,
          output: target == "result" ? bad : nil), signatures: [selected])
      }
    }
  }

  // Given two roles with different domains, when they share one authored field, then both consumers must accept its entire domain.
  @Test func sharedReferencesMustSatisfyEveryConsumingConstraint() throws {
    let selected = try signature(["count": ["minimum": 1, "maximum": 10, "integer": true],
      "other": ["minimum": 5, "maximum": 20, "integer": true]])
    let accepted = try NativeScalarRoles.normalizeRoles(payload(["reference": "shared"],
      other: number("shared", value: 6, minimum: 5, maximum: 10)), signatures: [selected])
    #expect(accepted.roles["measure"]?["inputs"] == ["count": "shared", "other": "shared"])
    for field in [number("shared", value: 6, minimum: 1, maximum: 10), number("shared", value: 6, minimum: 5, maximum: 20)] {
      #expect(throws: (any Error).self) {
        try NativeScalarRoles.normalizeRoles(payload(["reference": "shared"], other: field), signatures: [selected])
      }
    }
  }

  // Given shared declarations across capabilities, when a later consumer has narrower limits, then validate that consumer too.
  @Test func validatesReferencesAcrossCapabilities() throws {
    let first = CalculationRegistry.Signature(id: "first", inputs: ["count": .number], outputs: [:],
      inputNumberConstraints: ["count": .init(minimum: 1, maximum: 10, integer: true)])
    let second = CalculationRegistry.Signature(id: "second", inputs: ["count": .number], outputs: [:],
      inputNumberConstraints: ["count": .init(minimum: 5, maximum: 20, integer: true)])
    for minimum in [1.0, 5.0] {
      let data = try encode(["declarations": [
        "first": ["inputs": ["count": number("shared", value: 6, minimum: minimum)], "outputs": [:]],
        "second": ["inputs": ["count": ["reference": "shared"]], "outputs": [:]],
      ]])
      if minimum == 5 {
        let accepted = try NativeScalarRoles.normalizeRoles(data, signatures: [second, first])
        #expect(accepted.roles["second"]?["inputs"]?["count"] == "shared")
      } else {
        #expect(throws: UIError.self) { try NativeScalarRoles.normalizeRoles(data, signatures: [second, first]) }
      }
    }
  }

  // Given invalid host metadata, when either native entry point runs, then validate metadata without relying on registration.
  @Test func rejectsInvalidMetadataIndependently() throws {
    for constraint in [
      InputNumberConstraint(minimum: 10, maximum: 1),
      .init(minimum: .nan, maximum: 10), .init(minimum: 1, maximum: .infinity),
      .init(minimum: -1_000_000_001, maximum: 10), .init(minimum: 1, maximum: 1_000_000_001),
      .init(minimum: 1.5, maximum: 10, integer: true), .init(minimum: 1, maximum: 9.5, integer: true),
      .init(minimum: 1, maximum: 10, step: 0), .init(minimum: 1, maximum: 10, step: -1),
      .init(minimum: 1, maximum: 10, step: .nan), .init(minimum: 1, maximum: 10, step: .infinity),
      .init(minimum: 1, maximum: 10, step: 1_000_000_001),
      .init(minimum: 1, maximum: 10, integer: true, step: 0.5),
    ] {
      let selected = CalculationRegistry.Signature(id: "measure", inputs: ["count": .number, "other": .number],
        outputs: ["result": .number], inputNumberConstraints: ["count": constraint])
      #expect(throws: UIError.self) { try NativeScalarRoles.roleSchema(signatures: [selected]) }
      #expect(throws: UIError.self) { try NativeScalarRoles.normalizeRoles(payload(number("count")), signatures: [selected]) }
    }
  }

  // Given independently constructed signature metadata, when either native entry point runs, then invalid metadata fails before role processing.
  @Test func rejectsUnknownAndNonNumberConstraintTargets() throws {
    for (target, inputs) in [("missing", ["count": "number", "other": "number"]),
      ("count", ["count": "text", "other": "number"]), ("result", ["count": "number", "other": "number"])] {
      let selected = try signature([target: ["minimum": 1, "maximum": 10]], inputs: inputs)
      #expect(throws: (any Error).self) { try NativeScalarRoles.roleSchema(signatures: [selected]) }
      #expect(throws: (any Error).self) { try NativeScalarRoles.normalizeRoles(payload(number("count")), signatures: [selected]) }
    }
  }
}
