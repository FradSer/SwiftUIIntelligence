import Foundation
import Testing
import Observation
import Synchronization
@testable import SwiftUIIntelligence

private func previewJSON(_ text: String = "Preview", state: String = "") -> Data {
  Data("{\"version\":1,\"root\":{\"id\":\"answer\",\"type\":\"text\",\"text\":\"\(text)\"}\(state),\"floatingActions\":[]}".utf8)
}

/// Gates observe callback completion, not elapsed time. Cancellation is deliberately ignored.
private actor PreviewGate: ProgressiveDocumentGenerationProvider, StreamingDocumentGenerationProvider {
  private var callback: (@Sendable (DocumentPreviewEvent) async -> Void)?
  private var attemptID = UUID()
  private var completion: CheckedContinuation<Data, any Error>?
  private var readyWaiters: [CheckedContinuation<Void, Never>] = []

  func generate(_ request: DocumentGenerationRequest) async throws -> Data {
    throw UIError("The progressive overload must be selected.")
  }
  func generate(_ request: DocumentGenerationRequest, onSnapshot: @escaping @Sendable (Data) -> Void) async throws -> Data {
    throw UIError("Cumulative streaming must not be selected.")
  }
  func generate(_ request: DocumentGenerationRequest, onPreviewEvent: @escaping @Sendable (DocumentPreviewEvent) async -> Void) async throws -> Data {
    callback = onPreviewEvent
    return try await withCheckedThrowingContinuation { continuation in
      completion = continuation
      let waiters = readyWaiters
      readyWaiters = []
      for waiter in waiters { waiter.resume() }
    }
  }
  func waitUntilReady(beginAttempt: Bool = true) async {
    if completion == nil {
      await withCheckedContinuation { readyWaiters.append($0) }
    }
    if beginAttempt { await begin(UUID()) }
  }
  func begin(_ id: UUID) async {
    attemptID = id
    await callback?(.begin(attemptID: id))
  }
  func currentCallback() -> (@Sendable (DocumentPreviewEvent) async -> Void)? { callback }
  func emit(_ sequence: Int, _ data: Data, attemptID: UUID? = nil) async {
    await callback?(.component(DocumentPreviewFrame(attemptID: attemptID ?? self.attemptID, sequence: sequence, data: data)))
  }
  func finish(_ result: Result<Data, any Error>) {
    let continuation = completion
    completion = nil
    continuation?.resume(with: result)
  }
}

@Test @MainActor func callerCancellationRejectsFramesFromIgnoringProvider() async {
  let provider = PreviewGate()
  let session = DocumentChatSession(provider: provider, timeout: nil)
  let work = Task { await session.send("Cancel caller") }
  await provider.waitUntilReady()
  await provider.emit(1, previewJSON("Before cancellation"))
  #expect(session.preview != nil)
  work.cancel()
  await provider.emit(2, previewJSON("After cancellation"))
  #expect(session.preview == nil)
  #expect(session.phase == .idle)
  await provider.finish(.success(previewJSON("Late final")))
  await work.value
  #expect(session.document == nil && session.revision == 0)
}

@Test @MainActor func cancellationDuringValidationPreventsPreviewPublication() async {
  let entered = DispatchSemaphore(value: 0)
  let released = DispatchSemaphore(value: 0)
  let provider = PreviewGate()
  let session = DocumentChatSession(provider: provider, sourceValidation: { _ in
    entered.signal()
    released.wait()
  }, timeout: nil)
  let work = Task { await session.send("Cancel during validation") }
  await provider.waitUntilReady()
  @Sendable func cancelWhenValidationStarts() {
    entered.wait()
    work.cancel()
    released.signal()
  }
  let cancellation = Task.detached { cancelWhenValidationStarts() }
  let published = Mutex(false)
  withObservationTracking { _ = session.preview } onChange: { published.withLock { $0 = true } }
  await provider.emit(1, previewJSON("Never publish"))
  #expect(!published.withLock { $0 })
  // The callback completes before the caller's main-actor cleanup must run.
  #expect(session.preview == nil && session.previewComponents.isEmpty)
  await cancellation.value
  await provider.finish(.failure(CancellationError()))
  await work.value
  #expect(session.document == nil && session.revision == 0)
}

@Test @MainActor func cancelledCallerCannotClearNextRequestsPreview() async {
  let provider = PreviewGate()
  let session = DocumentChatSession(provider: provider, timeout: nil)
  let old = Task { await session.send("Old request") }
  await provider.waitUntilReady()
  let oldCallback = await provider.currentCallback()
  old.cancel()
  session.cancel()
  await provider.finish(.success(previewJSON("Ignored old final")))
  await old.value
  let next = Task { await session.send("New request") }
  await provider.waitUntilReady()
  await provider.emit(1, previewJSON("New preview"))
  await oldCallback?(.begin(attemptID: UUID()))
  #expect(session.phase == .generating)
  #expect(session.preview?.root.text == "New preview")
  await provider.finish(.success(previewJSON("New final")))
  await next.value
  #expect(session.document?.root.text == "New final" && session.revision == 1)
}

@Test @MainActor func previewAttemptRejectsDuplicateComponentIDs() async {
  let provider = PreviewGate()
  let session = DocumentChatSession(provider: provider, timeout: nil)
  let work = Task { await session.send("Unique components") }
  await provider.waitUntilReady()
  await provider.emit(1, previewJSON("First"))
  await provider.emit(2, previewJSON("Same component ID"))
  #expect(session.previewComponents.count == 1)
  #expect(session.preview?.root.text == "First")
  await provider.finish(.success(previewJSON("Final")))
  await work.value
}

@Test @MainActor func rejectedFramesConsumeValidationBudget() async {
  let provider = PreviewGate()
  let session = DocumentChatSession(provider: provider, timeout: nil)
  let work = Task { await session.send("Bound preview validation") }
  await provider.waitUntilReady()
  for sequence in 1...32 { await provider.emit(sequence, Data("{".utf8)) }
  await provider.emit(33, previewJSON("Must not be decoded"))
  #expect(session.preview == nil)
  await provider.finish(.success(previewJSON("Final remains valid")))
  await work.value
  #expect(session.phase == .ready && session.document?.root.text == "Final remains valid")
}

@Test @MainActor func progressivePreviewIsSeparateFromCommittedDocument() async {
  // Given a provider that also supports cumulative streaming, when a complete frame arrives,
  // then only preview state changes, and callback completion observes the accepted frame.
  // Final layout requirements do not apply to the preview component.
  let provider = PreviewGate()
  let session = DocumentChatSession(provider: provider, requirements: .init(components: [.callout]), timeout: nil)
  let work = Task { await session.send("Explain the answer") }
  await provider.waitUntilReady()
  await provider.emit(1, previewJSON())
  #expect(session.preview?.root.text == "Preview" && session.previewSequence == 1)
  #expect(DocumentPreviewFrame(attemptID: UUID(), sequence: 1, data: previewJSON()).isReadOnly)
  #expect(session.previewComponents.count == 1)
  #expect(session.document == nil && session.documentJSON == nil && session.revision == 0)
  #expect(session.messages.count == 1 && session.phase == .generating)
  #expect(session.snapshotCount == 0 && session.errorMessage == nil)
  let final = Data(#"{"version":1,"root":{"id":"answer","type":"callout","text":"Final","tone":"note"},"floatingActions":[]}"#.utf8)
  await provider.finish(.success(final))
  await work.value
  #expect(session.document?.root.text == "Final" && session.revision == 1)
  #expect(session.messages.count == 2 && session.phase == .ready)
  #expect(session.preview == nil && session.previewSequence == nil)
}

@Test @MainActor func progressivePreviewRejectsInvalidFramesWithoutFailingGeneration() async throws {
  // Given exact source constraints, when malformed or unsafe frames arrive, then no preview
  // is exposed. A later valid final document can still commit.
  let provider = PreviewGate()
  let source = ",\"state\":[{\"id\":\"source\",\"kind\":\"number\",\"value\":2}]"
  let registry = try CalculationRegistry([
    .init(id: "reject", inputs: [:], outputs: ["value": .number]) { _ in
      throw UIError("Registry evaluation rejected this frame")
    }
  ])
  let session = DocumentChatSession(provider: provider, calculations: registry, requirements: .init(stateCount: 1, stateKinds: [.number]), sourceValidation: { document in
    guard document.state.first?.value == .number(2) else { throw UIError("Changed source") }
  }, declarationValidation: { document in
    guard document.state.first?.id == "source" else { throw UIError("Changed declaration") }
  }, timeout: nil)
  let work = Task { await session.send("Keep the source") }
  await provider.waitUntilReady()
  let invalidFrames = [
    Data("{".utf8),
    Data(#"{"version":1,"root":{"id":"action","type":"button","title":"Run","action":"unknown"}}"#.utf8),
    previewJSON(),
    previewJSON(state: ",\"state\":[{\"id\":\"source\",\"kind\":\"text\",\"value\":\"2\"}]"),
    previewJSON(state: source.replacingOccurrences(of: "value\":2", with: "value\":3")),
    previewJSON(state: source.replacingOccurrences(of: "source", with: "changed")),
    Data(repeating: 32, count: 65_537),
    Data(String(decoding: previewJSON(state: source), as: UTF8.self).replacingOccurrences(
      of: "\"floatingActions\":[]", with: #""calculations":[{"id":"binding","capability":"reject","inputs":{},"outputs":{"value":"source"}}],"floatingActions":[]"#).utf8),
  ]
  for (index, frame) in invalidFrames.enumerated() {
    await provider.emit(index + 1, frame)
    #expect(session.preview == nil && session.previewSequence == nil)
    #expect(session.phase == .generating && session.errorMessage == nil)
  }
  await provider.emit(9, previewJSON(state: source))
  #expect(session.previewSequence == 9)
  await provider.emit(10, Data("{".utf8))
  #expect(session.previewSequence == 9 && session.preview?.root.text == "Preview")
  await provider.finish(.success(previewJSON("Final", state: source)))
  await work.value
  #expect(session.phase == .ready && session.revision == 1 && session.preview == nil)
}

@Test @MainActor func progressivePreviewSequencesArePositiveAndMonotonic() async {
  // Given one request, when frames are duplicated or reordered, then the newest accepted
  // preview remains unchanged. A new request starts a new sequence.
  let provider = PreviewGate()
  let session = DocumentChatSession(provider: provider, timeout: nil)
  for _ in 0..<2 {
    let work = Task { await session.send("Explain") }
    await provider.waitUntilReady()
    await provider.emit(0, previewJSON("Zero"))
    await provider.emit(-1, previewJSON("Negative"))
    #expect(session.preview == nil)
    await provider.emit(2, previewJSON("Newest"))
    await provider.emit(1, previewJSON("Old"))
    await provider.emit(2, previewJSON("Duplicate"))
    #expect(session.preview?.root.text == "Newest" && session.previewSequence == 2)
    await provider.finish(.success(previewJSON("Final")))
    await work.value
  }
  #expect(session.revision == 2)
}

@Test @MainActor func progressiveFinalFailureRetainsPriorDocumentAndClearsPreview() async {
  // Given a committed document, when a preview passes declaration checks but final semantic
  // checks fail, then the prior committed revision and assistant history remain intact.
  let provider = PreviewGate()
  let session = DocumentChatSession(provider: provider, semanticValidation: { document in
    guard document.root.text == "Final" else { throw UIError("Incomplete final answer") }
  }, timeout: nil)
  let first = Task { await session.send("Explain") }
  await provider.waitUntilReady()
  await provider.finish(.success(previewJSON("Final")))
  await first.value
  let committed = session.documentJSON
  let work = Task { await session.send("Revise") }
  await provider.waitUntilReady()
  await provider.emit(1, previewJSON())
  #expect(session.preview != nil && session.documentJSON == committed)
  await provider.finish(.success(previewJSON()))
  await work.value
  #expect(session.phase == .failed && session.failureKind == .invalidDocument)
  #expect(session.preview == nil && session.previewSequence == nil)
  #expect(session.documentJSON == committed && session.revision == 1)
  #expect(session.messages.filter { $0.role == .assistant }.count == 1)
}

@Test @MainActor func cancelledProgressiveRequestCannotExposeLateFrames() async {
  // Given a provider that ignores cancellation, when it emits after cancellation or during
  // a newer request, then its frames and final result cannot change session state.
  let oldProvider = PreviewGate()
  let session = DocumentChatSession(provider: oldProvider, timeout: nil)
  let oldWork = Task { await session.send("Old request") }
  await oldProvider.waitUntilReady()
  await oldProvider.emit(1, previewJSON())
  let lateCallback = await oldProvider.currentCallback()
  session.cancel()
  #expect(session.preview == nil && session.previewSequence == nil && session.phase == .idle)
  await oldProvider.emit(2, previewJSON("Late"))
  #expect(session.preview == nil)
  await oldProvider.finish(.success(previewJSON("Late final")))
  await oldWork.value
  #expect(session.document == nil && session.revision == 0 && session.phase == .idle)
  let nextWork = Task { await session.send("New request") }
  await oldProvider.waitUntilReady()
  await oldProvider.emit(1, previewJSON("New preview"))
  await lateCallback?(.begin(attemptID: UUID()))
  await lateCallback?(.component(DocumentPreviewFrame(attemptID: UUID(), sequence: 99, data: previewJSON("Old late preview"))))
  #expect(session.preview?.root.text == "New preview" && session.previewSequence == 1)
  await oldProvider.finish(.success(previewJSON("New final")))
  await nextWork.value
  #expect(session.document?.root.text == "New final" && session.revision == 1)
}

@Test @MainActor func progressiveAttemptsRequireBeginAndRetireOldIDs() async {
  // Given explicit attempts, when a new attempt begins, then visible components reset,
  // retired IDs cannot restart, and stale or unannounced components cannot enter it.
  let provider = PreviewGate()
  let session = DocumentChatSession(provider: provider, timeout: nil)
  let work = Task { await session.send("Explain") }
  await provider.waitUntilReady(beginAttempt: false)
  let first = UUID(), second = UUID()
  await provider.emit(1, previewJSON(), attemptID: first)
  #expect(session.previewComponents.isEmpty)
  await provider.begin(first)
  await provider.emit(1, previewJSON("First"))
  await provider.emit(2, Data(String(decoding: previewJSON("Second"), as: UTF8.self).replacingOccurrences(of: "\"id\":\"answer\"", with: "\"id\":\"second\"").utf8))
  #expect(session.previewComponents.map { $0.root.text } == ["First", "Second"])
  await provider.begin(first)
  #expect(session.previewComponents.count == 2) // Duplicate begin is not a reset.
  await provider.begin(second)
  #expect(session.previewComponents.isEmpty && session.preview == nil && session.previewSequence == nil)
  await provider.emit(3, previewJSON("Stale"), attemptID: first)
  await provider.begin(first)
  await provider.emit(4, previewJSON("Retired"), attemptID: first)
  #expect(session.previewComponents.isEmpty)
  await provider.emit(1, previewJSON("Fresh"), attemptID: second)
  #expect(session.previewComponents.map { $0.root.text } == ["Fresh"])
  let lastAttempt = UUID()
  for _ in 0..<29 { await provider.begin(UUID()) }
  await provider.begin(lastAttempt) // 32 accepted attempts, including first and second.
  await provider.emit(1, previewJSON("Last allowed"), attemptID: lastAttempt)
  let overflow = UUID()
  await provider.begin(overflow)
  await provider.emit(1, previewJSON("Too many attempts"), attemptID: overflow)
  #expect(session.preview?.root.text == "Last allowed")
  await provider.finish(.success(previewJSON("Final")))
  await work.value
  #expect(session.previewComponents.isEmpty)
  await provider.emit(2, previewJSON("After final"), attemptID: second)
  await provider.begin(UUID())
  #expect(session.previewComponents.isEmpty && session.revision == 1)
}

@Test @MainActor func progressiveAttemptFreezesAllDeclarations() async throws {
  // Given an accepted component, when state, records, or calculations change in that
  // attempt, then the component is rejected. A new attempt can establish new declarations.
  let provider = PreviewGate()
  let registry = try CalculationRegistry([
    .init(id: "constant", inputs: [:], outputs: ["value": .number]) { _ in ["value": .number(2)] }
  ])
  let session = DocumentChatSession(provider: provider, calculations: registry, timeout: nil)
  let work = Task { await session.send("Explain") }
  await provider.waitUntilReady()
  await provider.emit(1, previewJSON())
  let state = ",\"state\":[{\"id\":\"output\",\"kind\":\"number\",\"value\":2}]"
  let records = #","records":[{"id":"rows","schema":{"fields":{"name":"text"}},"rows":[]}]"#
  await provider.emit(2, previewJSON(state: state))
  await provider.emit(3, previewJSON(state: records))
  #expect(session.previewComponents.count == 1 && session.previewSequence == 1)
  await provider.begin(UUID())
  await provider.emit(1, previewJSON(state: state))
  let calculations = #","calculations":[{"id":"binding","capability":"constant","inputs":{},"outputs":{"value":"output"}}]"#
  await provider.emit(2, previewJSON(state: state + calculations))
  #expect(session.previewComponents.count == 1 && session.previewSequence == 1)
  await provider.emit(3, Data(String(decoding: previewJSON("Same declarations", state: state), as: UTF8.self).replacingOccurrences(of: "\"id\":\"answer\"", with: "\"id\":\"other\"").utf8))
  #expect(session.previewComponents.count == 2 && session.previewSequence == 3)
  await provider.finish(.success(previewJSON("Final")))
  await work.value
}

@Test @MainActor func progressiveAcceptedBudgetsPersistAcrossAttempts() async {
  // Given bounded accepted previews, when count or bytes exceed the request budget,
  // then more components are ignored even after an attempt reset. Final output is independent.
  for byteLimit in [false, true] {
    let provider = PreviewGate()
    let session = DocumentChatSession(provider: provider, timeout: nil)
    let work = Task { await session.send("Explain") }
    await provider.waitUntilReady()
    let small = previewJSON()
    var frame = small
    if byteLimit { frame.append(Data(repeating: 32, count: 32_768 - frame.count)) }
    let accepted = byteLimit ? 2 : 32
    for sequence in 1...accepted {
      let unique = Data(String(decoding: frame, as: UTF8.self).replacingOccurrences(of: "\"id\":\"answer\"", with: "\"id\":\"n\(String(format: "%05d", sequence))\"").utf8)
      await provider.emit(sequence, unique)
    }
    #expect(session.previewComponents.count == accepted)
    await provider.emit(accepted + 1, frame)
    #expect(session.previewComponents.count == accepted)
    await provider.begin(UUID())
    await provider.emit(1, small)
    #expect(session.previewComponents.isEmpty)
    await provider.finish(.success(previewJSON("Final")))
    await work.value
    #expect(session.phase == .ready && session.revision == 1)
    let next = Task { await session.send("Next request") }
    await provider.waitUntilReady()
    await provider.emit(1, small)
    #expect(session.previewComponents.count == 1)
    await provider.finish(.success(previewJSON("Next final")))
    await next.value
  }
}
