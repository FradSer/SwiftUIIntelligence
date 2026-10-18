import Foundation
import SwiftUI
@testable import SwiftUIIntelligence
import SwiftUIIntelligenceFoundationModels
import Synchronization
import Testing

@Suite struct ConvenienceValidationTests {
  private static let json = Data(#"{"version":1,"root":{"id":"root","type":"text","text":"Accepted"}}"#.utf8)

  @Test @MainActor func publicInitializersPreserveDefaultsAndExposeValidation() {
    // Given existing callers, when either convenience view is initialized, defaults still compile.
    func requireView<V: View>(_ view: V) {}
    let provider = ChatResponseProvider { _ in String(decoding: Self.json, as: UTF8.self) }
    requireView(GeneratedDocumentView(provider: provider))
    requireView(GeneratedDocumentView(provider: provider, semanticValidation: { _ in }))
    requireView(OnDeviceGeneratedView())
    // Given host-owned provenance, both wrappers accept an explicit provider label.
    requireView(GeneratedDocumentView(provider: provider, providerLabel: "Synthetic provider · not AI generation"))
    requireView(OnDeviceGeneratedView(providerLabel: "Apple on-device model"))
    let session = DocumentChatSession(provider: provider)
    requireView(GeneratedDocumentView(session: session, actions: ActionRegistry([:]), state: DocumentState(), calculations: nil))
    requireView(GeneratedDocumentView(session: session, actions: ActionRegistry([:]), state: DocumentState(), providerLabel: "Host test provider"))

    // Given staged host policies, both public initializers accept the same validation options.
    requireView(GeneratedDocumentView(provider: provider, requirements: .init(exactText: ["Accepted"]),
      sourceInputValidation: { _, _, _ in }, sourceValidation: { _ in },
      declarationValidation: { _ in }, semanticValidation: { _ in }))
    requireView(OnDeviceGeneratedView(requirements: .init(exactText: ["Accepted"]),
      sourceInputValidation: { _, _, _ in }, sourceValidation: { _ in },
      declarationValidation: { _ in }, semanticValidation: { _ in }))
    requireView(GeneratedDocumentView(provider: provider, sourceInputValidation: nil))
    requireView(OnDeviceGeneratedView(sourceInputValidation: nil))
  }

  @Test @MainActor func sessionFactoryForwardsEarlyAndFinalValidation() async throws {
    // Given a fake provider, when it validates stages and returns a document,
    // then the convenience session receives each policy and still validates final acceptance.
    let events = Mutex<[String]>([])
    let collection = try JSONDecoder().decode(RecordCollection.self, from: Data(#"{"id":"items","schema":{"fields":{"amount":"number"}},"rows":[{"id":"one","values":{"amount":125}}]}"#.utf8))
    let registry = try CalculationRegistry([.init(id: "total", inputs: [:], outputs: ["total": .number],
      recordInputs: ["items": .init(fields: ["amount": .number])], recordOutputs: [:]) { _, _ in
        CalculationResult(values: ["total": .number(0)])
      }])
    let provider = ChatResponseProvider { request in
      #expect(request.requirements.exactText == ["Accepted"])
      try request.validateSourceInput(capability: "total", input: "items", collection: collection)
      let document = try UIDocument.decode(Self.json, registeredActions: [])
      try request.validateSource(document)
      try request.validateDeclarations(document)
      #expect(events.withLock { $0 } == ["input", "source", "source", "declaration"])
      return String(decoding: Self.json, as: UTF8.self)
    }
    let session = GeneratedDocumentView.makeSession(provider: provider, calculations: registry,
      requirements: .init(exactText: ["Accepted"]),
      sourceInputValidation: { capability, input, actual in
        #expect(capability == "total" && input == "items" && actual.id == "items")
        events.withLock { $0.append("input") }
      }, sourceValidation: { _ in events.withLock { $0.append("source") } },
      declarationValidation: { _ in events.withLock { $0.append("declaration") } },
      semanticValidation: { _ in events.withLock { $0.append("semantic") } })
    await session.send("Generate")
    #expect(session.phase == .ready)
    #expect(session.revision == 1)
    #expect(events.withLock { $0 } == ["input", "source", "source", "declaration", "source", "declaration", "semantic"])
  }

  @Test @MainActor func finalAcceptanceDoesNotBypassForwardedPolicy() async {
    // Given a provider that skips validation, final acceptance must enforce the host policy.
    let provider = ChatResponseProvider { _ in String(decoding: Self.json, as: UTF8.self) }
    let session = GeneratedDocumentView.makeSession(provider: provider, sourceValidation: { _ in
      throw UIError("Host source rejected.")
    })
    await session.send("Generate")
    #expect(session.phase == .failed)
    #expect(session.failureKind == .invalidDocument)
    #expect(session.document == nil && session.revision == 0)
    #expect(session.errorMessage?.contains("Host source rejected.") == true)
  }
}
