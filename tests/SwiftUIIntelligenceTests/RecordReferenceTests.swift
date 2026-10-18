import Foundation
import Testing
import SwiftUIIntelligence

private let referenceSchemas: [String: RecordSchema] = [
  "items": .init(fields: ["owner": .text]),
  "people": .init(fields: ["name": .text]),
]
private let ownerReference = RecordInputReference(input: "items", field: "owner", targetInput: "people")

@Test @MainActor func unknownRecordReferenceRejectsBeforeCallback() throws {
  var calls = 0
  let registry = try CalculationRegistry([
    .init(id: "check", inputs: [:], outputs: ["ok": .boolean], recordInputs: referenceSchemas,
      recordOutputs: [:], recordReferences: [ownerReference]) { _, _ in
      calls += 1
      return .init(values: ["ok": .boolean(true)])
    }
  ])
  // Given valid row shapes, an unknown target ID must fail before the callback.
  #expect(throws: UIError.self) {
    try registry.evaluate("check", inputs: [:], records: [
      "items": [.init(id: "tea", values: ["owner": .text("Alice")])],
      "people": [.init(id: "person-1", values: ["name": .text("Alice")])],
    ])
  }
  #expect(calls == 0)
}

@Test @MainActor func recordReferencesPreserveExactValuesAndPropagateMetadata() throws {
  var received: [String: [RecordRow]] = [:]
  let registry = try CalculationRegistry([
    .init(id: "check", inputs: [:], outputs: ["ok": .boolean], recordInputs: referenceSchemas,
      recordOutputs: [:], recordReferences: [ownerReference]) { _, records in
      received = records
      return .init(values: ["ok": .boolean(true)])
    }
  ])
  let records: [String: [RecordRow]] = [
    "items": [.init(id: "tea", values: ["owner": .text("person-1")])],
    "people": [.init(id: "person-1", values: ["name": .text("Alice")])],
  ]
  // Given a target row ID, evaluation passes the original rows without inference.
  _ = try registry.evaluate("check", inputs: [:], records: records)
  #expect(received == records)
  let signature = try #require(registry.signatures.first)
  #expect(signature.recordReferences.first?.targetInput == "people")
  let decoded = try JSONDecoder().decode(CalculationRegistry.Signature.self, from: JSONEncoder().encode(signature))
  #expect(decoded.recordReferences.first?.field == "owner")
  _ = try DocumentGenerationRequest(messages: [.init(role: .user, content: "Check rows")], calculationSignatures: [decoded])
}

@Test @MainActor func invalidRecordReferenceMetadataRejectsRegistrationAndRequests() throws {
  let invalid: [[RecordInputReference]] = [
    [.init(input: "missing", field: "owner", targetInput: "people")],
    [.init(input: "items", field: "missing", targetInput: "people")],
    [.init(input: "items", field: "owner", targetInput: "missing")],
    [.init(input: "bad id", field: "owner", targetInput: "people")],
    [.init(input: "items", field: "bad field", targetInput: "people")],
    [.init(input: "items", field: "owner", targetInput: "bad target")],
    [ownerReference, ownerReference],
    [ownerReference, .init(input: "items", field: "owner", targetInput: "items")],
    [.init(input: "items", field: "owner", targetInput: "items")],
    [ownerReference, .init(input: "people", field: "name", targetInput: "items")],
  ]
  // Given invalid metadata, both registration boundaries reject it without execution.
  for references in invalid {
    #expect(throws: UIError.self) {
      try CalculationRegistry([
        .init(id: "check", inputs: [:], outputs: ["ok": .boolean], recordInputs: referenceSchemas,
          recordOutputs: [:], recordReferences: references) { _, _ in .init(values: ["ok": .boolean(true)]) }
      ])
    }
    #expect(throws: UIError.self) {
      try DocumentGenerationRequest(messages: [.init(role: .user, content: "Check rows")], calculationSignatures: [
        .init(id: "check", inputs: [:], outputs: ["ok": .boolean], recordInputs: referenceSchemas, recordReferences: references)
      ])
    }
  }
  for kind in [CalculationRegistry.ValueKind.number, .boolean] {
    let schemas: [String: RecordSchema] = ["items": .init(fields: ["owner": kind]), "people": referenceSchemas["people"]!]
    #expect(throws: UIError.self) {
      try CalculationRegistry([
        .init(id: "check", inputs: [:], outputs: ["ok": .boolean], recordInputs: schemas,
          recordOutputs: [:], recordReferences: [ownerReference]) { _, _ in .init(values: ["ok": .boolean(true)]) }
      ])
    }
    #expect(throws: UIError.self) {
      try DocumentGenerationRequest(messages: [.init(role: .user, content: "Check rows")], calculationSignatures: [
        .init(id: "check", inputs: [:], outputs: ["ok": .boolean], recordInputs: schemas, recordReferences: [ownerReference])
      ])
    }
  }
}

@Test func recordReferenceSignatureDecodingDefaultsOnlyWhenOmitted() throws {
  let legacy = #"{"id":"check","inputs":{},"outputs":{"ok":"boolean"}}"#
  let signature = try JSONDecoder().decode(CalculationRegistry.Signature.self, from: Data(legacy.utf8))
  #expect(signature.recordReferences.isEmpty)
  for extra in [#", "recordReferences":null"#, #", "unexpected":[]"#] {
    #expect(throws: (any Error).self) {
      try JSONDecoder().decode(CalculationRegistry.Signature.self, from: Data((String(legacy.dropLast()) + extra + "}").utf8))
    }
  }
  #expect(throws: (any Error).self) {
    try JSONDecoder().decode(RecordInputReference.self,
      from: Data(#"{"input":"items","field":"owner","targetInput":"people","unexpected":true}"#.utf8))
  }
}

@Test @MainActor func emptyReferenceTargetsRequireEmptySourceRows() throws {
  var calls = 0
  let registry = try CalculationRegistry([
    .init(id: "check", inputs: [:], outputs: ["ok": .boolean], recordInputs: referenceSchemas,
      recordOutputs: [:], recordReferences: [ownerReference]) { _, _ in
      calls += 1
      return .init(values: ["ok": .boolean(true)])
    }
  ])
  // Given no target rows, a populated source fails; two empty inputs remain valid.
  #expect(throws: UIError.self) {
    try registry.evaluate("check", inputs: [:], records: [
      "items": [.init(id: "tea", values: ["owner": .text("")])], "people": [],
    ])
  }
  #expect(calls == 0)
  _ = try registry.evaluate("check", inputs: [:], records: ["items": [], "people": []])
  #expect(calls == 1)
}
