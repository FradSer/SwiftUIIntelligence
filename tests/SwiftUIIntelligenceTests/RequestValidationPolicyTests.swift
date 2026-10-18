import Foundation
import SwiftUIIntelligence
import Testing
import Observation
import Synchronization

@Test @MainActor func cancelledCallerCannotCommitDuringSynchronousFinalGate() async {
  let entered = DispatchSemaphore(value: 0)
  let released = DispatchSemaphore(value: 0)
  let provider = PolicyProvider([#"{"version":1,"root":{"id":"root","type":"text","text":"Never commit"}}"#])
  let session = DocumentChatSession(provider: provider, timeout: nil)
  let policy = DocumentValidationPolicy(finalValidation: { _ in
    entered.signal()
    released.wait()
  })
  let work = Task { await session.send("Cancel at final gate", validation: policy) }
  let committed = Mutex(false)
  withObservationTracking { _ = session.document } onChange: { committed.withLock { $0 = true } }
  @Sendable func cancelAtGate() {
    if entered.wait(timeout: .now() + 5) == .success { work.cancel() }
    released.signal()
  }
  let cancellation = Task.detached { cancelAtGate() }
  await work.value
  await cancellation.value
  #expect(!committed.withLock { $0 })
  #expect(session.document == nil && session.documentJSON == nil && session.revision == 0)
  #expect(!session.messages.contains { $0.role == .assistant })
}

private actor PolicyProvider: DocumentGenerationProvider {
  private var outputs: [String]
  private var requests: [DocumentGenerationRequest] = []

  init(_ outputs: [String]) { self.outputs = outputs }

  func generate(_ request: DocumentGenerationRequest) async throws -> Data {
    requests.append(request)
    guard !outputs.isEmpty else { throw UIError("No test output remains") }
    return Data(outputs.removeFirst().utf8)
  }

  func capturedRequests() -> [DocumentGenerationRequest] { requests }
}

@Suite struct RequestValidationPolicyTests {
  @Test(arguments: [false, true]) @MainActor
  func finalGateCanCancelOrResetWithoutLateCommit(reset: Bool) async {
    let provider = PolicyProvider([Self.json("Never commit")])
    let session = DocumentChatSession(provider: provider, timeout: nil)
    let policy = DocumentValidationPolicy(finalValidation: { _ in
      if reset { session.reset() } else { session.cancel() }
    })
    await session.send("Cancel from gate", validation: policy)
    #expect(session.document == nil && session.documentJSON == nil && session.revision == 0)
    #expect(!session.messages.contains { $0.role == .assistant })
    #expect(session.phase == .idle)
    if reset { #expect(session.messages.isEmpty) }
  }

  private static func json(_ text: String) -> String {
    "{\"version\":1,\"root\":{\"id\":\"answer\",\"type\":\"text\",\"text\":\"\(text)\"},\"floatingActions\":[]}"
  }

  private static func document(_ text: String) throws -> UIDocument {
    try UIDocument.decode(Data(json(text).utf8), registeredActions: [])
  }

  private static func policy(_ text: String, components: Set<UINode.Kind> = []) -> DocumentValidationPolicy {
    DocumentValidationPolicy(requirements: .init(components: components), sourceValidation: { document in
      guard document.root.text == text else { throw UIError("Source rejected \(text)") }
    }, declarationValidation: { document in
      guard document.root.text == text else { throw UIError("Declarations rejected \(text)") }
    }, semanticValidation: { document in
      guard document.root.text == text else { throw UIError("Semantics rejected \(text)") }
    })
  }

  // Given two explicit policies, when one session sends both, then providers see distinct
  // requirements and each captured request keeps its own callbacks after selection changes.
  @Test @MainActor func explicitPoliciesFreezeRequirementsAndCallbacks() async throws {
    let provider = PolicyProvider([Self.json("First"), Self.json("Second")])
    let session = DocumentChatSession(provider: provider)
    var selected = Self.policy("First", components: [.text])
    await session.send("First request", validation: selected)
    #expect(session.phase == .ready)
    selected = Self.policy("Second")
    await session.send("Second request", validation: selected)
    #expect(session.phase == .ready && session.revision == 2)
    let requests = await provider.capturedRequests()
    try #require(requests.count == 2)
    #expect(requests[0].requirements.components != requests[1].requirements.components)
    try requests[0].validateSemantics(Self.document("First"))
    try requests[1].validateSemantics(Self.document("Second"))
    #expect(throws: UIError.self) { try requests[0].validateSource(Self.document("Second")) }
    #expect(throws: UIError.self) { try requests[1].validateSource(Self.document("First")) }
    #expect(requests[1].messages.count == 3)
  }

  // Given a rejected override, when UI selection changes and retry runs, then retry keeps
  // the failed policy and history. A later plain send restores the session baseline.
  @Test @MainActor func retryFreezesFailedPolicyAndPlainSendRestoresBaseline() async throws {
    let provider = PolicyProvider([Self.json("Baseline"), Self.json("Wrong"), Self.json("Override"), Self.json("Baseline")])
    let session = DocumentChatSession(provider: provider, requirements: .init(components: [.text]), semanticValidation: { document in
      guard document.root.text == "Baseline" else { throw UIError("Baseline rejected") }
    })
    await session.send("Initial")
    #expect(session.phase == .ready)
    let accepted = session.documentJSON
    let history = session.messages
    var selected = Self.policy("Override")
    await session.send("Revision", validation: selected)
    #expect(session.phase == .failed && session.failureKind == .invalidDocument && session.canRetry)
    #expect(session.documentJSON == accepted && session.revision == 1)
    #expect(Array(session.messages.prefix(history.count)) == history)
    #expect(session.messages.count == history.count + 1 && session.messages.last?.role == .user)
    selected = Self.policy("Next selection", components: [.callout])
    await session.retry()
    #expect(session.phase == .ready && session.document?.root.text == "Override")
    #expect(session.revision == 2 && session.messages.count == 4)
    await session.send("Use baseline")
    #expect(session.phase == .ready && session.document?.root.text == "Baseline" && session.revision == 3)
    let requests = await provider.capturedRequests()
    try #require(requests.count == 4)
    #expect(requests[1].messages == requests[2].messages)
    #expect(requests[0].requirements.components == requests[3].requirements.components)
    try requests[2].validateSemantics(Self.document("Override"))
    #expect(throws: UIError.self) { try requests[3].validateSemantics(Self.document("Override")) }
    // Selection stays local to the main actor; no Sendable callback captures this variable.
    _ = selected
  }

  // Given all provider-facing callbacks, when the provider checks a captured request,
  // then each stage uses the override, including the isolated source-input callback.
  @Test @MainActor func providerReceivesEveryValidationStage() async throws {
    let provider = PolicyProvider([Self.json("Accepted")])
    let schema = RecordSchema(fields: ["amount": .number])
    let registry = try CalculationRegistry([.init(id: "total", inputs: [:], outputs: ["value": .number], recordInputs: ["items": schema], recordOutputs: [:]) { _, _ in
      CalculationResult(values: ["value": .number(0)])
    }])
    let session = DocumentChatSession(provider: provider, calculations: registry,
      sourceInputValidation: { _, _, _ in throw UIError("Baseline input") })
    let policy = DocumentValidationPolicy(sourceInputValidation: { capability, input, collection in
      #expect(capability == "total" && input == "items")
      guard collection.rows.first?.values["amount"] == .number(125) else { throw UIError("Override input") }
    }, sourceValidation: { document in
      if document.root.text == "Source" { throw UIError("Override source") }
    }, declarationValidation: { document in
      if document.root.text == "Declaration" { throw UIError("Override declaration") }
    }, semanticValidation: { document in
      if document.root.text == "Semantic" { throw UIError("Override semantic") }
    })
    await session.send("Override", validation: policy)
    #expect(session.phase == .ready)
    let requests = await provider.capturedRequests()
    let request = try #require(requests.first)
    let collection = try JSONDecoder().decode(RecordCollection.self, from: Data(#"{"id":"items","schema":{"fields":{"amount":"number"}},"rows":[{"id":"tea","values":{"amount":125}}]}"#.utf8))
    try request.validateSourceInput(capability: "total", input: "items", collection: collection)
    for text in ["Source", "Declaration", "Semantic"] {
      #expect(throws: UIError.self) { try request.validateSemantics(Self.document(text)) }
    }
    try request.validateSource(Self.document("Declaration"))
    try request.validateDeclarations(Self.document("Semantic"))
  }

  // Given a final actor-isolated gate, when it rejects a revision, then no commit occurs.
  // A changed local selection cannot replace the gate saved for retry.
  @Test @MainActor func finalGateRejectsBeforeCommitAndIsFrozenForRetry() async throws {
    let provider = PolicyProvider([Self.json("Initial"), Self.json("Rejected"), Self.json("Allowed"), Self.json("Plain")])
    let session = DocumentChatSession(provider: provider)
    await session.send("Initial")
    let accepted = session.documentJSON
    let history = session.messages
    let registry = try CalculationRegistry([])
    var selected = DocumentValidationPolicy(finalValidation: { @MainActor document in
      // Actor-bound host state can be used without sending it to a provider.
      #expect(registry.names.isEmpty)
      guard document.root.text == "Allowed" else { throw UIError("Final gate rejected") }
    })
    await session.send("Revise", validation: selected)
    #expect(session.phase == .failed && session.failureKind == .invalidDocument && session.canRetry)
    #expect(session.documentJSON == accepted && session.revision == 1)
    #expect(Array(session.messages.prefix(history.count)) == history)
    #expect(session.messages.count == history.count + 1)
    #expect(session.errorMessage == "Final gate rejected")
    selected = DocumentValidationPolicy(finalValidation: { _ in throw UIError("Next gate") })
    await session.retry()
    #expect(session.phase == .ready && session.document?.root.text == "Allowed" && session.revision == 2)
    let requests = await provider.capturedRequests()
    try requests[1].validateSemantics(Self.document("Rejected"))
    #expect(requests[1].messages == requests[2].messages)
    await session.send("Plain")
    #expect(session.phase == .ready && session.document?.root.text == "Plain" && session.revision == 3)
    _ = selected
  }

  // Given rejecting baseline callbacks, when an empty policy overrides them, then all
  // policy defaults are no-ops. An explicit nil policy still uses the baseline.
  @Test @MainActor func defaultPolicyReplacesRatherThanMergesBaseline() async {
    let provider = PolicyProvider([Self.json("Accepted"), Self.json("Rejected")])
    let session = DocumentChatSession(provider: provider, requirements: .init(components: [.callout]),
      sourceValidation: { _ in throw UIError("Baseline source") },
      declarationValidation: { _ in throw UIError("Baseline declaration") },
      semanticValidation: { _ in throw UIError("Baseline semantic") })
    await session.send("Override", validation: DocumentValidationPolicy())
    #expect(session.phase == .ready && session.revision == 1)
    await session.send("Baseline", validation: nil)
    #expect(session.phase == .failed && session.failureKind == .invalidDocument)
    #expect(session.document?.root.text == "Accepted" && session.revision == 1)
  }
}
