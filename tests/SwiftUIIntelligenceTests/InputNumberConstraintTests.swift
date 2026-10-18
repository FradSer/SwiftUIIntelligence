import Foundation
import Testing
@testable import SwiftUIIntelligence

private func constraintField(_ declaration: String) throws -> StateField {
  try JSONDecoder().decode(StateField.self, from: Data(declaration.utf8))
}

@Test func inputNumberConstraintExactDecodingAndRoundTrip() throws {
  let decoder = JSONDecoder()
  let basic = try decoder.decode(InputNumberConstraint.self, from: Data(#"{"minimum":1,"maximum":9}"#.utf8))
  #expect(basic == InputNumberConstraint(minimum: 1, maximum: 9))
  #expect(!basic.integer && basic.step == nil)
  let full = InputNumberConstraint(minimum: -4, maximum: 8, integer: true, step: 2)
  #expect(try decoder.decode(InputNumberConstraint.self, from: JSONEncoder().encode(full)) == full)
  for json in [#"{"maximum":9}"#, #"{"minimum":1}"#, #"{"minimum":null,"maximum":9}"#,
    #"{"minimum":1,"maximum":9,"integer":null}"#, #"{"minimum":1,"maximum":9,"step":null}"#,
    #"{"minimum":1,"maximum":9,"other":0}"#] {
    #expect(throws: (any Error).self) { try decoder.decode(InputNumberConstraint.self, from: Data(json.utf8)) }
  }
  let legacy = #"{"id":"check","inputs":{"n":"number"},"outputs":{"ok":"boolean"}}"#
  #expect(try decoder.decode(CalculationRegistry.Signature.self, from: Data(legacy.utf8)).inputNumberConstraints.isEmpty)
  #expect(throws: (any Error).self) {
    try decoder.decode(CalculationRegistry.Signature.self, from: Data((String(legacy.dropLast()) + #", "inputNumberConstraints":null}"#).utf8))
  }
}

@Test @MainActor func inputNumberConstraintMetadataRegistrationAndExport() throws {
  let constraint = InputNumberConstraint(minimum: 1, maximum: 9, integer: true, step: 2)
  let capability = CalculationRegistry.Capability(id: "check", inputs: ["n": .number], outputs: ["ok": .boolean], inputNumberConstraints: ["n": constraint]) { _ in ["ok": .boolean(true)] }
  let registry = try CalculationRegistry([capability])
  let signature = try #require(registry.signatures.first)
  #expect(signature.inputNumberConstraints == ["n": constraint])
  #expect(try JSONDecoder().decode(CalculationRegistry.Signature.self, from: JSONEncoder().encode(signature)).inputNumberConstraints == ["n": constraint])
  let outputOnly = CalculationRegistry.Capability(id: "rows", inputs: ["n": .number], outputs: [:], recordOutputs: ["rows": .init(fields: ["name": .text])], inputNumberConstraints: ["n": constraint]) { _ in .init(values: [:], records: ["rows": []]) }
  let withRecords = CalculationRegistry.Capability(id: "records", inputs: ["n": .number], outputs: ["ok": .boolean], recordInputs: [:], recordOutputs: [:], inputNumberConstraints: ["n": constraint]) { _, _ in .init(values: ["ok": .boolean(true)]) }
  #expect(outputOnly.inputNumberConstraints == ["n": constraint])
  #expect(withRecords.inputNumberConstraints == ["n": constraint])
  let legacy = CalculationRegistry.Capability(id: "legacy", inputs: [:], outputs: ["ok": .boolean]) { _ in ["ok": .boolean(true)] }
  #expect(legacy.inputNumberConstraints.isEmpty)
  try InputNumberConstraint(minimum: -1e9, maximum: 1e9, integer: true, step: 1e9).validate()
  let invalid: [InputNumberConstraint] = [
    .init(minimum: 2, maximum: 1), .init(minimum: -.infinity, maximum: 1), .init(minimum: 0, maximum: .nan),
    .init(minimum: -1e9 - 1, maximum: 1), .init(minimum: 0, maximum: 1e9 + 1),
    .init(minimum: 0.5, maximum: 9, integer: true), .init(minimum: 0, maximum: 9.5, integer: true),
    .init(minimum: 0, maximum: 9, step: 0), .init(minimum: 0, maximum: 9, step: -1),
    .init(minimum: 0, maximum: 9, step: .infinity), .init(minimum: 0, maximum: 9, step: 1e9 + 1),
    .init(minimum: 0, maximum: 9, integer: true, step: 0.5)
  ]
  // Given invalid metadata, registration rejects it before a callback can run.
  for value in invalid {
    #expect(throws: UIError.self) {
      try CalculationRegistry([.init(id: "check", inputs: ["n": .number], outputs: ["ok": .boolean], inputNumberConstraints: ["n": value]) { _ in ["ok": .boolean(true)] }])
    }
  }
  for inputs: [String: CalculationRegistry.ValueKind] in [[:], ["n": .text], ["n": .boolean], ["n": .instant]] {
    #expect(throws: UIError.self) {
      try CalculationRegistry([.init(id: "check", inputs: inputs, outputs: ["ok": .boolean], inputNumberConstraints: ["n": constraint]) { _ in ["ok": .boolean(true)] }])
    }
  }
}

@Test @MainActor func inputNumberConstraintsCheckRuntimeBeforeCallbackWithoutStepLattice() throws {
  var calls = 0
  let registry = try CalculationRegistry([.init(id: "check", inputs: ["n": .number], outputs: ["ok": .boolean], inputNumberConstraints: ["n": .init(minimum: 1, maximum: 9, integer: true, step: 2)]) { _ in
    calls += 1
    return ["ok": .boolean(true)]
  }])
  for value in [0.0, 10, 1.5, .infinity, .nan] {
    #expect(throws: UIError.self) { try registry.evaluate("check", inputs: ["n": .number(value)]) }
  }
  #expect(calls == 0)
  // Step describes the control, not a runtime value lattice.
  for value in [1.0, 2, 9] { _ = try registry.evaluate("check", inputs: ["n": .number(value)]) }
  #expect(calls == 3)
}

@Test func inputNumberConstraintFieldValidation() throws {
  let constraint = InputNumberConstraint(minimum: 1, maximum: 9, integer: true, step: 2)
  try constraint.validate(field: constraintField(#"{"id":"n","kind":"number","value":2,"minimum":1,"maximum":9,"step":2}"#))
  let invalid = [
    #"{"id":"n","kind":"text","value":"2"}"#,
    #"{"id":"n","kind":"number","value":2,"minimum":0,"maximum":9,"step":2}"#,
    #"{"id":"n","kind":"number","value":2,"minimum":1,"maximum":10,"step":2}"#,
    #"{"id":"n","kind":"number","value":2,"minimum":3,"maximum":1,"step":2}"#,
    #"{"id":"n","kind":"number","value":2,"minimum":1.5,"maximum":9,"step":2}"#,
    #"{"id":"n","kind":"number","value":2,"minimum":1,"maximum":8.5,"step":2}"#,
    #"{"id":"n","kind":"number","value":2,"minimum":1,"maximum":9,"step":1}"#,
    #"{"id":"n","kind":"number","value":2.5,"minimum":1,"maximum":9,"step":2}"#,
    #"{"id":"n","kind":"number","value":0,"minimum":1,"maximum":9,"step":2}"#,
    #"{"id":"n","kind":"number","value":8,"minimum":1,"maximum":7,"step":2}"#
  ]
  for json in invalid {
    #expect(throws: UIError.self) { try constraint.validate(field: constraintField(json)) }
  }
  let integerWithoutStep = InputNumberConstraint(minimum: 1, maximum: 9, integer: true)
  #expect(throws: UIError.self) {
    try integerWithoutStep.validate(field: constraintField(#"{"id":"n","kind":"number","value":2,"minimum":1,"maximum":9,"step":0.5}"#))
  }
  try InputNumberConstraint(minimum: 0, maximum: 9).validate(field: constraintField(#"{"id":"n","kind":"number","value":2.25,"minimum":0.5,"maximum":8.5,"step":0.25}"#))
}

@Test @MainActor func invalidIntegerEditPreservesDerivedRecordsWithoutCallingHost() throws {
  var calls = 0
  let registry = try CalculationRegistry([.init(id: "scale", inputs: ["count": .number], outputs: [:],
    recordOutputs: ["result": .init(fields: ["quantity": .number])],
    inputNumberConstraints: ["count": .init(minimum: 1, maximum: 9, integer: true, step: 1)]) { values in
      calls += 1
      return CalculationResult(values: [:], records: ["result": [.init(id: "row", values: ["quantity": values["count"]!])]])
    }])
  let json = #"{"version":1,"state":[{"id":"count","kind":"number","value":2,"minimum":1,"maximum":9,"step":1}],"calculations":[{"id":"scale","capability":"scale","inputs":{"count":"count"},"outputs":{},"recordOutputs":{"result":"derived"}}],"root":{"id":"root","type":"text","text":"Quantity"}}"#
  let document = try UIDocument.decode(Data(json.utf8), registeredActions: [], registeredCalculations: registry.names)
  let state = DocumentState()
  try state.load(document, calculations: registry)
  let previousValues = state.values
  let previousRows = state.records["derived"]
  let previousCalls = calls
  #expect(throws: UIError.self) { try state.set("count", to: .number(2.5)) }
  #expect(state.values == previousValues)
  #expect(state.records["derived"] == previousRows)
  #expect(calls == previousCalls)
  try state.set("count", to: .number(3))
  #expect(state.records["derived"]?.first?.values["quantity"] == .number(3))
}

@Test @MainActor func inputNumberConstraintPlanAndStateRollback() throws {
  var calls = 0
  let registry = try CalculationRegistry([.init(id: "check", inputs: ["n": .number], outputs: ["out": .number], inputNumberConstraints: ["n": .init(minimum: 1, maximum: 9, integer: true)]) { inputs in
    calls += 1
    return ["out": inputs["n"]!]
  }])
  let json = #"{"version":1,"state":[{"id":"n","kind":"number","value":2,"minimum":1,"maximum":9},{"id":"out","kind":"number","value":0}],"root":{"id":"root","type":"text","text":"Check"}}"#
  let document = try UIDocument.decode(Data(json.utf8), registeredActions: [])
  let bindings = [CalculationBinding(id: "check", capability: "check", inputs: ["n": "n"], outputs: ["out": "out"])]
  let state = DocumentState()
  try state.load(document, calculations: registry, bindings: bindings)
  try state.set("n", to: .number(3))
  let previous = state.values
  let previousCalls = calls
  #expect(throws: UIError.self) { try state.set("n", to: .number(3.5)) }
  #expect(state.values == previous && calls == previousCalls)
  // Given a wider declaration, a replacement load fails before evaluation and keeps the old plan.
  let wider = try UIDocument.decode(Data(json.replacingOccurrences(of: "\"maximum\":9", with: "\"maximum\":10").utf8), registeredActions: [])
  #expect(throws: UIError.self) { try state.load(wider, calculations: registry, bindings: bindings) }
  #expect(state.values == previous && calls == previousCalls)
  try state.set("n", to: .number(4))
  #expect(state.values == ["n": .number(4), "out": .number(4)])
}
