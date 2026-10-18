import Foundation
import SwiftUIIntelligence
import Testing

@Test @MainActor func rawSubmissionByteLimitCannotBeBypassedWithWhitespace() async {
  let provider = ChatResponseProvider { _ in #"{"version":1,"root":{"id":"root","type":"text","text":"Accepted"}}"# }
  let session = DocumentChatSession(provider: provider)
  let limit = String(repeating: " ", count: 47_999) + "x"
  await session.send(limit)
  #expect(session.originalSources == [limit])
  #expect(session.revision == 1)
  await session.send(" " + limit)
  #expect(session.phase == .failed && session.failureKind == .input)
  #expect(session.originalSources == [limit])
  #expect(session.revision == 1)
}

@Test @MainActor func failedSubmissionsCannotGrowOriginalArchiveBeyondBudget() async {
  let provider = OriginalSourceProvider(failures: 30)
  let session = DocumentChatSession(provider: provider)
  let source = String(repeating: " ", count: 47_999) + "x"
  for _ in 0..<24 { await session.send(source) }
  #expect(session.originalSources.count == 24)
  #expect(session.originalSources.reduce(0) { $0 + $1.utf8.count } == 1_152_000)
  let history = session.messages
  let calls = await provider.requests.count
  await session.send("Next")
  #expect(session.failureKind == .input)
  #expect(session.originalSources.count == 24)
  #expect(session.canRetry)
  #expect(session.messages == history)
  #expect(await provider.requests.count == calls)
  await session.retry()
  #expect(await provider.requests.count == calls + 1)
  #expect(await provider.requests.last?.messages.last?.content == "x")
  #expect(session.originalSources.count == 24)
  session.reset()
  await session.send("After reset")
  #expect(session.originalSources == ["After reset"])
}

private let originalSourceJSON = #"{"version":1,"root":{"id":"answer","type":"text","text":"Model output, not the source"}}"#

private actor OriginalSourceProvider: DocumentGenerationProvider {
  private var failures: Int
  private(set) var requests: [DocumentGenerationRequest] = []

  init(failures: Int = 0) { self.failures = failures }

  func generate(_ request: DocumentGenerationRequest) async throws -> Data {
    requests.append(request)
    if failures > 0 {
      failures -= 1
      throw UIError("Synthetic provider failure")
    }
    return Data(originalSourceJSON.utf8)
  }
}

private actor OriginalSourceGate: DocumentGenerationProvider {
  private var continuation: CheckedContinuation<Data, Never>?
  private(set) var started = false

  func generate(_ request: DocumentGenerationRequest) async throws -> Data {
    await withCheckedContinuation { continuation in
      self.continuation = continuation
      started = true
    }
  }

  func release() {
    continuation?.resume(returning: Data(originalSourceJSON.utf8))
    continuation = nil
  }
}

@Suite struct OriginalSourceTests {
  // Given exact source passages, when two follow-ups finish, then raw sources remain
  // complete and ordered while provider messages retain the existing trimming rule.
  @Test @MainActor func exactSourcesAreSeparateFromTrimmedModelHistory() async {
    let provider = OriginalSourceProvider()
    let session = DocumentChatSession(provider: provider, timeout: nil)
    #expect(session.originalSources.isEmpty)
    let sources = ["  First passage\nwith a second line. \n", "\n Follow-up one\t", "  Follow-up two\n\n"]
    for source in sources { await session.send(source) }
    #expect(session.originalSources == sources)
    #expect(session.revision == 3)
    let requests = await provider.requests
    #expect(requests.count == 3)
    #expect(requests.last?.messages.filter { $0.role == .user }.map(\.content) == sources.map {
      $0.trimmingCharacters(in: .whitespacesAndNewlines)
    })
    #expect(!session.originalSources.contains("Model output, not the source"))
  }

  // Given failed requests, when retry or a replacement send runs, then only each new
  // accepted send adds a source; provider failure cannot remove the original passage.
  @Test @MainActor func failureRetainsSourcesAndRetryDoesNotAppend() async {
    let provider = OriginalSourceProvider(failures: 2)
    let session = DocumentChatSession(provider: provider, timeout: nil)
    await session.send(" First failed source \n")
    #expect(session.failureKind == .provider)
    #expect(session.originalSources == [" First failed source \n"])
    await session.send(" Second failed source \n")
    #expect(session.failureKind == .provider)
    #expect(session.originalSources == [" First failed source \n", " Second failed source \n"])
    await session.retry()
    #expect(session.phase == .ready)
    #expect(session.originalSources == [" First failed source \n", " Second failed source \n"])
    let requests = await provider.requests
    #expect(requests.count == 3)
    #expect(requests[1].messages == requests[2].messages)
    #expect(requests[1].messages.map(\.content) == ["Second failed source"])
  }

  // Given stored sources, when request construction rejects input, then storage is unchanged.
  @Test @MainActor func invalidInputDoesNotAppend() async {
    let provider = OriginalSourceProvider()
    let session = DocumentChatSession(provider: provider, timeout: nil)
    await session.send(" Original \n")
    for invalid in ["", " \n\t ", String(repeating: "x", count: 48_001)] {
      await session.send(invalid)
      #expect(session.failureKind == .input)
      #expect(session.originalSources == [" Original \n"])
    }
    #expect(await provider.requests.count == 1)
    session.reset()
    #expect(session.originalSources.isEmpty)
  }

  // Given padded raw input, when its UTF-8 size exceeds 48,000 bytes, then input
  // validation rejects it without retaining a source or calling the provider.
  @Test @MainActor func rawByteLimitRejectsPaddingAndAcceptsExactBoundary() async {
    let provider = OriginalSourceProvider()
    let session = DocumentChatSession(provider: provider, timeout: nil)
    let boundary = String(repeating: " ", count: 47_997) + "猫"
    #expect(boundary.utf8.count == 48_000)
    await session.send(boundary + "\n")
    #expect(session.phase == .failed && session.failureKind == .input)
    #expect(session.errorMessage == "Conversation needs a final user message, at most 24 messages and 48 KiB of content.")
    #expect(session.originalSources.isEmpty && session.messages.isEmpty)
    #expect(await provider.requests.isEmpty)
    await session.send(boundary)
    #expect(session.phase == .ready)
    #expect(session.originalSources == [boundary])
    let requests = await provider.requests
    #expect(requests.count == 1)
    #expect(requests.first?.messages.map(\.content) == ["猫"])
  }

  // Given an in-flight request, when send is ignored and reset invalidates a late
  // provider completion, then no ignored or late source appears after reset.
  @Test @MainActor func generatingGuardAndResetPreventLateAppend() async {
    let provider = OriginalSourceGate()
    let session = DocumentChatSession(provider: provider, timeout: nil)
    let work = Task { await session.send(" In-flight \n") }
    while !(await provider.started) { await Task.yield() }
    #expect(session.originalSources == [" In-flight \n"])
    await session.send("Ignored")
    #expect(session.originalSources == [" In-flight \n"])
    session.reset()
    #expect(session.originalSources.isEmpty)
    await provider.release()
    await work.value
    #expect(session.originalSources.isEmpty)
    #expect(session.messages.isEmpty && session.document == nil && session.phase == .idle)
  }

  // Given a final policy gate, when it cancels or resets, then reset clears sources
  // before the provider returns and cancellation alone retains the accepted input.
  @Test(arguments: [false, true]) @MainActor
  func finalGateCannotRestoreSourcesAfterReset(reset: Bool) async {
    let session = DocumentChatSession(provider: OriginalSourceProvider(), timeout: nil)
    let source = " Exact gate source \n"
    let policy = DocumentValidationPolicy(finalValidation: { _ in
      #expect(session.originalSources == [source])
      if reset { session.reset() } else { session.cancel() }
    })
    await session.send(source, validation: policy)
    #expect(session.originalSources == (reset ? [] : [source]))
    #expect(session.document == nil && session.revision == 0 && session.phase == .idle)
  }
}
