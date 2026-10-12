import Foundation
import Observation

@MainActor @Observable public final class DocumentChatSession {
  public enum Phase: Equatable, Sendable { case idle, generating, ready, failed }
  public enum FailureKind: Equatable, Sendable { case input, provider, invalidDocument }
  public private(set) var phase: Phase = .idle
  public private(set) var failureKind: FailureKind?
  public private(set) var errorMessage: String?
  public private(set) var document: UIDocument?
  public private(set) var documentJSON: Data?
  public private(set) var messages: [ChatMessage] = []
  public private(set) var revision = 0
  public private(set) var snapshotCount = 0
  public private(set) var snapshotByteCount = 0
  public var canRetry: Bool { phase == .failed && pendingRequest != nil }
  private let provider: any DocumentGenerationProvider
  private let requirements: DocumentRequirements
  private let semanticValidation: @Sendable (UIDocument) throws -> Void
  private let timeout: Duration?
  private var timeoutTask: Task<Void, Never>?
  private var generationTask: Task<Data, Error>?
  private let registeredActions: Set<String>
  private var pendingRequest: DocumentGenerationRequest?
  private var requestID = UUID()

  public init(provider: any DocumentGenerationProvider, registeredActions: Set<String> = [], requirements: DocumentRequirements = .init(), semanticValidation: @escaping @Sendable (UIDocument) throws -> Void = { _ in }, timeout: Duration? = .seconds(300)) {
    self.timeout = timeout
    self.requirements = requirements
    self.semanticValidation = semanticValidation
    self.provider = provider
    self.registeredActions = registeredActions
  }

  /// One request at a time. A failed attempt retains the previous valid document.
  public func send(_ content: String) async {
    guard phase != .generating else { return }
    let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
    do {
      // A new message replaces the previous failed user attempt; retry never duplicates it.
      let committed = messages.last?.role == .user ? Array(messages.dropLast()) : messages
      let message = ChatMessage(role: .user, content: trimmed)
      let request = try DocumentGenerationRequest(
        messages: committed + [message], registeredActions: registeredActions, requirements: requirements, semanticValidation: semanticValidation)
      messages = request.messages
      pendingRequest = request
      await generate(request)
    } catch {
      pendingRequest = nil
      failureKind = .input
      errorMessage = error.localizedDescription
      phase = .failed
    }
  }

  public func retry() async {
    guard canRetry, let request = pendingRequest else { return }
    await generate(request)
  }

  /// Invalidate late completions (even providers that ignore task cancellation).
  public func cancel() {
    timeoutTask?.cancel(); timeoutTask = nil
    generationTask?.cancel(); generationTask = nil
    requestID = UUID()
    phase = document == nil ? .idle : .ready
  }

  public func reset() {
    cancel()
    requestID = UUID()
    pendingRequest = nil
    messages = []
    document = nil
    documentJSON = nil
    errorMessage = nil
    failureKind = nil
    revision = 0
    phase = .idle
  }

  private func generate(_ request: DocumentGenerationRequest) async {
    let id = UUID()
    requestID = id
    timeoutTask?.cancel()
    if let timeout {
      timeoutTask = Task { @MainActor [weak self] in
        do { try await Task.sleep(for: timeout) } catch { return }
        guard let self, self.requestID == id, self.phase == .generating else { return }
        self.generationTask?.cancel(); self.generationTask = nil
        self.requestID = UUID()
        self.failureKind = .provider; self.errorMessage = "Generation timed out. Retry is available."
        self.phase = .failed
      }
    }
    defer { if requestID == id { timeoutTask?.cancel(); timeoutTask = nil } }
    phase = .generating
    snapshotCount = 0; snapshotByteCount = 0
    failureKind = nil
    errorMessage = nil
    do {
      let task = Task { [self] in
        if let streaming = provider as? any StreamingDocumentGenerationProvider {
          return try await streaming.generate(request, onSnapshot: { data in
            Task { @MainActor [weak self] in
              guard let self, self.requestID == id, self.phase == .generating else { return }
              self.snapshotCount += 1; self.snapshotByteCount = data.count
            }
          })
        }
        return try await provider.generate(request)
      }
      generationTask = task
      let data = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
      try Task.checkCancellation()
      guard requestID == id else { return }
      let valid: UIDocument
      do {
        valid = try UIDocument.decode(data, registeredActions: registeredActions)
        try requirements.validate(valid)
        try semanticValidation(valid)
      } catch {
        failureKind = .invalidDocument
        throw error
      }
      let canonical = try DocumentGenerationContract.canonicalJSON(valid)
      document = valid
      documentJSON = canonical
      revision += 1
      // Context includes only validated documents, never malformed/rejected output.
      messages.append(
        ChatMessage(role: .assistant, content: String(decoding: canonical, as: UTF8.self)))
      generationTask = nil
      pendingRequest = nil
      phase = .ready
    } catch {
      guard requestID == id else { return }
      if error is CancellationError {
        phase = document == nil ? .idle : .ready
      } else {
        failureKind = failureKind ?? .provider
        errorMessage = error.localizedDescription
        phase = .failed
      }
    }
  }
}
