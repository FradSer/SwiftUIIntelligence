import Foundation
import SwiftUIIntelligence
@testable import SwiftUIIntelligenceFoundationModels
import Testing

private actor NativePreviewEvents {
  private var events: [DocumentPreviewEvent] = []

  func append(_ event: DocumentPreviewEvent) async {
    await Task.yield()
    events.append(event)
  }

  func collected() -> [DocumentPreviewEvent] { events }
}

@Suite struct NativeProgressiveProviderTests {
  // Given the native provider, when used through either protocol, then both contracts compile.
  @Test func supportsDistinctStreamingAndProgressiveContracts() {
    let provider = FoundationModelsDocumentProvider()
    let streaming: any StreamingDocumentGenerationProvider = provider
    let progressive: any ProgressiveDocumentGenerationProvider = provider
    #expect(type(of: streaming) == FoundationModelsDocumentProvider.self)
    #expect(type(of: progressive) == FoundationModelsDocumentProvider.self)
  }

  // Given accepted declarations and two leaves, when delivered, then callbacks finish in order
  // and each envelope retains its own leaf identity and all accepted declarations.
  @Test func awaitsCompleteComponentEnvelopesInSlotOrder() async throws {
    let events = NativePreviewEvents()
    let attempt = FoundationModelsDocumentProvider.PreviewAttempt(onPreviewEvent: { await events.append($0) })
    let declarations = Data(#"{"state":[{"id":"name","kind":"text","value":"Accepted"}],"records":[],"calculations":[]}"#.utf8)
    let layouts = [
      Data(#"{"version":1,"root":{"id":"first","type":"text","text":"First"},"floatingActions":[]}"#.utf8),
      Data(#"{"version":1,"root":{"id":"second","type":"text","text":"Second"},"floatingActions":[]}"#.utf8),
    ]
    try await attempt.begin()
    #expect(await events.collected().count == 1)
    for (index, layout) in layouts.enumerated() {
      let data = try NativeStagedSchema.assemble(declarations: declarations, layout: layout)
      _ = try UIDocument.decode(data, registeredActions: [])
      try await attempt.component(sequence: index + 1, data: data)
      #expect(await events.collected().count == index + 2)
    }
    let received = await events.collected()
    guard case .begin(let id) = received[0] else {
      Issue.record("Expected an attempt before components.")
      return
    }
    #expect(id == attempt.id)
    for (index, event) in received.dropFirst().enumerated() {
      guard case .component(let frame) = event else {
        Issue.record("Expected a complete component frame.")
        continue
      }
      #expect(frame.attemptID == id)
      #expect(frame.sequence == index + 1)
      #expect(frame.isReadOnly)
      let object = try #require(JSONSerialization.jsonObject(with: frame.data) as? [String: Any])
      let root = try #require(object["root"] as? [String: Any])
      #expect(root["id"] as? String == (index == 0 ? "first" : "second"))
      let expected = try #require(JSONSerialization.jsonObject(with: declarations) as? NSDictionary)
      for key in ["state", "records", "calculations"] {
        #expect(NSDictionary(dictionary: [key: try #require(object[key])]).isEqual(to: [key: try #require(expected[key])]))
      }
    }
  }

  // Given a layout retry, when the next attempt starts, then it uses a new identity.
  @Test func retriesUseDistinctAttemptIDs() async throws {
    let events = NativePreviewEvents()
    let first = FoundationModelsDocumentProvider.PreviewAttempt(onPreviewEvent: { await events.append($0) })
    let retry = FoundationModelsDocumentProvider.PreviewAttempt(onPreviewEvent: { await events.append($0) })
    try await first.begin()
    try await retry.begin()
    #expect(first.id != retry.id)
    #expect(await events.collected().count == 2)
  }

  // Given no progressive callback, when the legacy path delivers, then delivery is a no-op.
  @Test func absentCallbackDoesNotRequirePreviewData() async throws {
    let attempt = FoundationModelsDocumentProvider.PreviewAttempt(onPreviewEvent: nil)
    try await attempt.begin()
    try await attempt.component(sequence: 1, data: Data())
  }

  // Given cancellation before delivery, when beginning, then no callback runs.
  @Test func cancellationBeforeCallbackStopsDelivery() async {
    let events = NativePreviewEvents()
    let task = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      let attempt = FoundationModelsDocumentProvider.PreviewAttempt(onPreviewEvent: { await events.append($0) })
      try await attempt.begin()
    }
    switch await task.result {
    case .success: Issue.record("Expected cancellation before callback.")
    case .failure(let error): #expect(error is CancellationError)
    }
    #expect(await events.collected().isEmpty)
  }

  // Given cancellation inside an awaited callback, when it returns, then generation stops.
  @Test func cancellationAfterCallbackStopsDelivery() async {
    let events = NativePreviewEvents()
    let task = Task {
      let attempt = FoundationModelsDocumentProvider.PreviewAttempt(onPreviewEvent: {
        await events.append($0)
        withUnsafeCurrentTask { $0?.cancel() }
      })
      try await attempt.begin()
      try await attempt.component(sequence: 1, data: Data())
    }
    switch await task.result {
    case .success: Issue.record("Expected cancellation after callback.")
    case .failure(let error): #expect(error is CancellationError)
    }
    #expect(await events.collected().count == 1)
  }
}
