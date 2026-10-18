import Foundation
import SwiftUIIntelligence
import Testing

@Suite struct SourceInputValidationTests {
  private enum CallbackError: Error { case invoked }
  private static let schema = RecordSchema(fields: ["amount": .number])
  private static let signature = CalculationRegistry.Signature(id: "total", inputs: [:], outputs: ["total": .number], recordInputs: ["items": schema])

  private static func collection(amount: String = "125", fields: String = #"{"amount":"number"}"#) throws -> RecordCollection {
    try JSONDecoder().decode(RecordCollection.self, from: Data("{\"id\":\"items\",\"schema\":{\"fields\":\(fields)},\"rows\":[{\"id\":\"tea\",\"values\":{\"amount\":\(amount)}}]}".utf8))
  }

  private static func document(amount: Int, bound: Bool = true) -> String {
    let bindings = bound ? #", "calculations":[{"id":"sum","capability":"total","inputs":{},"outputs":{"total":"total"},"recordInputs":{"items":"items"}}]"# : ""
    return "{\"version\":1,\"state\":[{\"id\":\"total\",\"kind\":\"number\",\"value\":0}],\"records\":[{\"id\":\"items\",\"schema\":{\"fields\":{\"amount\":\"number\"}},\"rows\":[{\"id\":\"tea\",\"values\":{\"amount\":\(amount)}}]}]\(bindings),\"root\":{\"id\":\"root\",\"type\":\"text\",\"text\":\"Bill\"}}"
  }

  @Test func identifierOnlyRegistrationRetainsDefaultDeclarationCompatibility() throws {
    let document = try UIDocument.decode(Data(Self.document(amount: 125).utf8), registeredActions: [], registeredCalculations: ["total"])
    let request = try DocumentGenerationRequest(messages: [.init(role: .user, content: "Bill")], registeredCalculations: ["total"])
    try request.validateDeclarations(document)
    let optedIn = try DocumentGenerationRequest(messages: request.messages, registeredCalculations: ["total"],
      sourceInputValidation: { _, _, _ in throw CallbackError.invoked })
    #expect(throws: UIError.self) { try optedIn.validateDeclarations(document) }
  }

  // Given structurally valid but incorrect facts, only an explicit host policy rejects them.
  @Test func hostFactsAndDefaultCompatibility() throws {
    let collection = try Self.collection(amount: "999")
    let compatible = try DocumentGenerationRequest(messages: [.init(role: .user, content: "Bill")], calculationSignatures: [Self.signature])
    try compatible.validateSourceInput(capability: "total", input: "items", collection: collection)
    let strict = try DocumentGenerationRequest(messages: compatible.messages, calculationSignatures: [Self.signature], sourceInputValidation: { capability, input, collection in
      #expect(capability == "total" && input == "items")
      #expect(collection.id == "items" && collection.rows.first?.id == "tea")
      guard collection.rows.first?.values["amount"] == .number(125) else { throw UIError("Source amount changed.") }
    })
    #expect(throws: UIError.self) { try strict.validateSourceInput(capability: "total", input: "items", collection: collection) }
    try strict.validateSourceInput(capability: "total", input: "items", collection: Self.collection())
  }

  // Given invalid capability, parameter, schema, or rows, the host callback must not run.
  @Test func structuralChecksPrecedeCallback() throws {
    let request = try DocumentGenerationRequest(messages: [.init(role: .user, content: "Bill")], registeredCalculations: ["untyped"], calculationSignatures: [Self.signature], sourceInputValidation: { _, _, _ in throw CallbackError.invoked })
    for capability in ["missing", "untyped"] {
      #expect(throws: UIError.self) { try request.validateSourceInput(capability: capability, input: "items", collection: Self.collection()) }
    }
    #expect(throws: UIError.self) { try request.validateSourceInput(capability: "total", input: "missing", collection: Self.collection()) }
    #expect(throws: UIError.self) { try request.validateSourceInput(capability: "total", input: "items", collection: Self.collection(fields: #"{"amount":"text"}"#)) }
    #expect(throws: UIError.self) { try request.validateSourceInput(capability: "total", input: "items", collection: Self.collection(amount: #""125""#)) }
    #expect(throws: CallbackError.self) { try request.validateSourceInput(capability: "total", input: "items", collection: Self.collection()) }
  }

  // Given one input in isolation, cross-input reference targets are not yet available.
  @Test func isolatedInputDoesNotInferReferenceTargets() throws {
    let signature = CalculationRegistry.Signature(id: "join", inputs: [:], outputs: ["total": .number], recordInputs: ["items": .init(fields: ["target": .text]), "targets": .init(fields: ["name": .text])], recordReferences: [.init(input: "items", field: "target", targetInput: "targets")])
    let request = try DocumentGenerationRequest(messages: [.init(role: .user, content: "Join")], calculationSignatures: [signature])
    let collection = try JSONDecoder().decode(RecordCollection.self, from: Data(#"{"id":"items","schema":{"fields":{"target":"text"}},"rows":[{"id":"one","values":{"target":"absent"}}]}"#.utf8))
    try request.validateSourceInput(capability: "join", input: "items", collection: collection)
  }

  // Given unbound collections or no calculations, declaration checks do not invent input roles.
  @Test func unboundSourcesDoNotInvokeCallback() throws {
    let request = try DocumentGenerationRequest(messages: [.init(role: .user, content: "Bill")], calculationSignatures: [Self.signature], sourceInputValidation: { _, _, _ in throw CallbackError.invoked })
    let document = try UIDocument.decode(Data(Self.document(amount: 999, bound: false).utf8), registeredActions: [])
    try request.validateSemantics(document)
  }

  // Given accepted bindings, declaration validation checks the actual mapped source after full-source validation.
  @Test func declarationsValidateBoundInputsAfterFullSource() throws {
    let document = try UIDocument.decode(Data(Self.document(amount: 125).utf8), registeredActions: [], registeredCalculations: ["total"])
    let request = try DocumentGenerationRequest(messages: [.init(role: .user, content: "Bill")], calculationSignatures: [Self.signature], sourceInputValidation: { _, _, _ in throw CallbackError.invoked })
    #expect(throws: CallbackError.self) { try request.validateDeclarations(document) }
    let sourceRejected = try DocumentGenerationRequest(messages: request.messages, calculationSignatures: [Self.signature], sourceInputValidation: { _, _, _ in throw CallbackError.invoked }, sourceValidation: { _ in throw UIError("Full source rejected.") })
    #expect(throws: UIError.self) { try sourceRejected.validateDeclarations(document) }
  }

  // Given a provider that never validates requests, final acceptance still rejects changed facts.
  @Test @MainActor func sessionRejectsInvalidSourceAndPreservesAcceptedHistory() async throws {
    let registry = try CalculationRegistry([.init(id: "total", inputs: [:], outputs: ["total": .number], recordInputs: ["items": Self.schema], recordOutputs: [:]) { _, _ in
      CalculationResult(values: ["total": .number(0)])
    }])
    let provider = ChatResponseProvider { request in Self.document(amount: request.messages.count == 1 ? 125 : 999) }
    let session = DocumentChatSession(provider: provider, calculations: registry, sourceInputValidation: { _, _, collection in
      guard collection.rows.first?.values["amount"] == .number(125) else { throw UIError("Source amount changed.") }
    })
    await session.send("Bill")
    #expect(session.phase == .ready && session.revision == 1)
    let accepted = session.documentJSON
    let history = session.messages
    await session.send("Revise")
    #expect(session.phase == .failed && session.failureKind == .invalidDocument)
    #expect(session.documentJSON == accepted && session.revision == 1 && session.canRetry)
    #expect(Array(session.messages.prefix(history.count)) == history)
    #expect(session.messages.count == history.count + 1 && session.messages.last?.role == .user)
    #expect(session.errorMessage?.contains("Source amount changed.") == true)
  }
}
