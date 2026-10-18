import Foundation
import Observation
import Synchronization

private final class GenerationCancellation: Sendable {
  private let cancelled = Mutex(false)
  func cancel() { cancelled.withLock { $0 = true } }
  var isCancelled: Bool { cancelled.withLock { $0 } }
}

@MainActor @Observable public final class DocumentChatSession {
  public enum Phase: Equatable, Sendable { case idle, generating, ready, failed }
  public enum FailureKind: Equatable, Sendable { case input, provider, invalidDocument }
  public private(set) var phase: Phase = .idle
  public private(set) var failureKind: FailureKind?
  public private(set) var errorMessage: String?
  public private(set) var document: UIDocument?
  /// Provisional, read-only content. Consumers must block action dispatch and interactions.
  /// This is the last accepted component, not an assembled partial document.
  public private(set) var preview: UIDocument?
  public private(set) var previewSequence: Int?
  /// Separate complete components in delivery order for the active attempt.
  public private(set) var previewComponents: [UIDocument] = []
  public private(set) var previewAttemptID: UUID?
  private var previewAttemptIDs: Set<UUID> = []
  private var previewValidationCount = 0
  private var previewValidationBytes = 0
  private var previewDeclarations: Data?
  public private(set) var documentJSON: Data?
  public private(set) var messages: [ChatMessage] = []
  /// Exact user input for each accepted send, including failed generation attempts.
  /// Each source has at most 48,000 UTF-8 bytes, including whitespace.
  /// Retry does not add a source. Reset clears all sources.
  /// Retains at most 24 passages and 1,152,000 UTF-8 bytes until reset; excess sends reject without truncation.
  public private(set) var originalSources: [String] = []
  public private(set) var revision = 0
  public private(set) var snapshotCount = 0
  public private(set) var snapshotByteCount = 0
  public var canRetry: Bool { phase == .failed && pendingRequest != nil }
  private let provider: any DocumentGenerationProvider
  private let baselineValidation: DocumentValidationPolicy
  private let timeout: Duration?
  private var timeoutTask: Task<Void, Never>?
  private var generationTask: Task<Data, Error>?
  private let registeredActions: Set<String>
  private let calculations: CalculationRegistry?
  /// The renderer uses this same immutable registry for the session lifetime.
  public var calculationRegistry: CalculationRegistry? { calculations }
  private struct PendingGeneration {
    let request: DocumentGenerationRequest
    let finalValidation: @MainActor @Sendable (UIDocument) throws -> Void
  }
  private var pendingRequest: PendingGeneration?
  private var requestID = UUID()
  private var callerCancellation: GenerationCancellation?

  public init(provider: any DocumentGenerationProvider, registeredActions: Set<String> = [], calculations: CalculationRegistry? = nil, requirements: DocumentRequirements = .init(), sourceInputValidation: (@Sendable (String, String, RecordCollection) throws -> Void)? = nil, sourceValidation: @escaping @Sendable (UIDocument) throws -> Void = { _ in }, declarationValidation: @escaping @Sendable (UIDocument) throws -> Void = { _ in }, semanticValidation: @escaping @Sendable (UIDocument) throws -> Void = { _ in }, timeout: Duration? = .seconds(300)) {
    self.calculations = calculations
    self.timeout = timeout
    self.baselineValidation = DocumentValidationPolicy(requirements: requirements,
      sourceInputValidation: sourceInputValidation, sourceValidation: sourceValidation,
      declarationValidation: declarationValidation, semanticValidation: semanticValidation)
    self.provider = provider
    self.registeredActions = registeredActions
  }

  /// One request at a time. A failed attempt retains the previous valid document.
  /// An explicit policy replaces the baseline for this request and its retries only.
  /// Input must have at most 48,000 UTF-8 bytes before whitespace is trimmed.
  public func send(_ content: String, validation: DocumentValidationPolicy? = nil) async {
    guard phase != .generating else { return }
    let policy = validation ?? baselineValidation
    guard originalSources.count < 24,
      content.utf8.count <= 1_152_000 - originalSources.reduce(0, { $0 + $1.utf8.count }) else {
      failureKind = .input
      errorMessage = "Original text retention is full. Start a new chat before sending more text."
      phase = .failed
      return
    }
    do {
      guard content.utf8.count <= 48_000 else {
        throw UIError("Conversation needs a final user message, at most 24 messages and 48 KiB of content.")
      }
      let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
      // A new message replaces the previous failed user attempt; retry never duplicates it.
      let committed = messages.last?.role == .user ? Array(messages.dropLast()) : messages
      let message = ChatMessage(role: .user, content: trimmed)
      let request = try DocumentGenerationRequest(
        messages: committed + [message], registeredActions: registeredActions, registeredCalculations: calculations?.names ?? [], calculationSignatures: calculations?.signatures ?? [], requirements: policy.requirements, sourceInputValidation: policy.sourceInputValidation, sourceValidation: policy.sourceValidation, declarationValidation: policy.declarationValidation, semanticValidation: policy.semanticValidation)
      let pending = PendingGeneration(request: request, finalValidation: policy.finalValidation)
      messages = request.messages
      pendingRequest = pending
      originalSources.append(content)
      await generate(pending)
    } catch {
      clearPreview()
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
    clearPreview()
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
    originalSources = []
    document = nil
    documentJSON = nil
    errorMessage = nil
    failureKind = nil
    revision = 0
    phase = .idle
  }

  private func clearPreviewComponents() {
    if preview != nil { preview = nil }
    if previewSequence != nil { previewSequence = nil }
    if !previewComponents.isEmpty { previewComponents = [] }
    previewDeclarations = nil
  }

  private func clearPreview() {
    clearPreviewComponents()
    previewAttemptID = nil
    previewAttemptIDs = []
    previewValidationCount = 0
    previewValidationBytes = 0
  }

  private struct PreviewDeclarations: Encodable {
    let state: [StateField]
    let records: [RecordCollection]
    let calculations: [CalculationBinding]
  }

  private func acceptPreview(_ event: DocumentPreviewEvent, request: DocumentGenerationRequest, id: UUID) {
    guard requestID == id, phase == .generating else { return }
    if callerCancellation?.isCancelled == true { cancel(); return }
    let frame: DocumentPreviewFrame
    switch event {
    case .begin(let attemptID):
      guard !previewAttemptIDs.contains(attemptID), previewAttemptIDs.count < 32 else { return }
      previewAttemptIDs.insert(attemptID)
      previewAttemptID = attemptID
      clearPreviewComponents()
      return
    case .component(let component):
      frame = component
    }
    guard frame.attemptID == previewAttemptID,
      frame.sequence > 0, frame.sequence > (previewSequence ?? 0),
      previewValidationCount < 32, frame.data.count <= 65_536 - previewValidationBytes else { return }
    previewValidationCount += 1
    previewValidationBytes += frame.data.count
    do {
      let valid = try UIDocument.decode(frame.data, registeredActions: request.registeredActions,
        registeredCalculations: request.registeredCalculations)
      guard !previewComponents.contains(where: { $0.root.id == valid.root.id }) else { return }
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys]
      let declarations = try encoder.encode(PreviewDeclarations(
        state: valid.state, records: valid.records, calculations: valid.calculations))
      guard previewDeclarations == nil || previewDeclarations == declarations else { return }
      try request.validateDeclarations(valid)
      if let calculations {
        let validationState = DocumentState()
        try validationState.load(valid, calculations: calculations, preservingEdits: false)
      }
      guard requestID == id, phase == .generating else { return }
      if callerCancellation?.isCancelled == true { cancel(); return }
      previewDeclarations = declarations
      previewComponents.append(valid)
      preview = valid
      previewSequence = frame.sequence
    } catch {
      // Rejected frames do not fail the request or replace an accepted preview.
    }
  }

  private func generate(_ pending: PendingGeneration) async {
    let request = pending.request
    let id = UUID()
    requestID = id
    let cancellation = GenerationCancellation()
    callerCancellation = cancellation
    clearPreview()
    timeoutTask?.cancel()
    if let timeout {
      timeoutTask = Task { @MainActor [weak self] in
        do { try await Task.sleep(for: timeout) } catch { return }
        guard let self, self.requestID == id, self.phase == .generating else { return }
        self.generationTask?.cancel(); self.generationTask = nil
        self.requestID = UUID()
        self.clearPreview()
        self.failureKind = .provider; self.errorMessage = "Generation timed out. Retry is available."
        self.phase = .failed
      }
    }
    defer {
      if requestID == id {
        timeoutTask?.cancel(); timeoutTask = nil
        generationTask = nil
        clearPreview()
      }
    }
    phase = .generating
    snapshotCount = 0; snapshotByteCount = 0
    failureKind = nil
    errorMessage = nil
    do {
      let task = Task { [self] in
        if let progressive = provider as? any ProgressiveDocumentGenerationProvider {
          return try await progressive.generate(request, onPreviewEvent: { [weak self] event in
            await self?.acceptPreview(event, request: request, id: id)
          })
        }
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
      let data = try await withTaskCancellationHandler { try await task.value } onCancel: {
        cancellation.cancel()
        task.cancel()
        Task { @MainActor [weak self] in
          guard let self, self.requestID == id else { return }
          self.cancel()
        }
      }
      try Task.checkCancellation()
      guard requestID == id else { return }
      let valid: UIDocument
      do {
        valid = try UIDocument.decode(data, registeredActions: registeredActions, registeredCalculations: calculations?.names ?? [])
        if let calculations {
          let validationState = DocumentState()
          try validationState.load(valid, calculations: calculations, preservingEdits: false)
        }
        try request.validateSemantics(valid)
        try pending.finalValidation(valid)
      } catch {
        failureKind = .invalidDocument
        throw error
      }
      try Task.checkCancellation()
      guard requestID == id, !cancellation.isCancelled else { throw CancellationError() }
      let canonical = try DocumentGenerationContract.canonicalJSON(valid)
      try Task.checkCancellation()
      guard requestID == id, !cancellation.isCancelled else { throw CancellationError() }
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
