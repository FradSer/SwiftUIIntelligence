import Foundation

/// One complete model-authored component in a complete document envelope.
/// Preserve the accepted state, record, and calculation declarations. The root must be a
/// complete component, not a placeholder built from partial JSON or cumulative token bytes.
public struct DocumentPreviewFrame: Sendable {
  public let attemptID: UUID
  public let sequence: Int
  public let data: Data
  /// Consumers must block action dispatch, controls, and navigation. Disabling views alone
  /// does not establish a read-only action boundary.
  public var isReadOnly: Bool { true }

  /// Use positive, strictly increasing sequence numbers within each explicit attempt.
  public init(attemptID: UUID, sequence: Int, data: Data) {
    self.attemptID = attemptID
    self.sequence = sequence
    self.data = data
  }
}

public enum DocumentPreviewEvent: Sendable {
  /// Begin a new attempt with a fresh ID. Duplicate or retired IDs do not reset previews.
  case begin(attemptID: UUID)
  case component(DocumentPreviewFrame)
}

/// A distinct preview channel, not cumulative JSON streaming.
public protocol ProgressiveDocumentGenerationProvider: DocumentGenerationProvider {
  /// Await each callback before sending the next event. Begin an attempt before components.
  /// Each frame contains complete document JSON with identical declarations in that attempt.
  /// Components require unique root IDs within each attempt and remain separate documents in delivery order; they never form a partial tree.
  /// Per request, the session accepts at most 32 attempts, 32 components, and 64 KiB of
  /// component bytes submitted for validation. Attempt changes do not reset validation budgets.
  /// Malformed or rejected frames consume those budgets once admitted for validation. Return the final document separately.
  /// Preview validation omits final layout and semantic completeness. Delivery must not
  /// execute actions or perform other document side effects.
  func generate(
    _ request: DocumentGenerationRequest,
    onPreviewEvent: @escaping @Sendable (DocumentPreviewEvent) async -> Void
  ) async throws -> Data
}
