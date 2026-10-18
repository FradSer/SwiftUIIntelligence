/// Immutable validation rules for one send and all retries of that request.
/// Provider-facing callbacks must be pure and can run more than once.
public struct DocumentValidationPolicy: Sendable {
  let requirements: DocumentRequirements
  let sourceInputValidation: (@Sendable (String, String, RecordCollection) throws -> Void)?
  let sourceValidation: @Sendable (UIDocument) throws -> Void
  let declarationValidation: @Sendable (UIDocument) throws -> Void
  let semanticValidation: @Sendable (UIDocument) throws -> Void
  let finalValidation: @MainActor @Sendable (UIDocument) throws -> Void

  /// The final gate runs only in the session, after all document checks and before commit.
  /// It is not sent to providers and does not validate provisional previews.
  public init(requirements: DocumentRequirements = .init(), sourceInputValidation: (@Sendable (String, String, RecordCollection) throws -> Void)? = nil, sourceValidation: @escaping @Sendable (UIDocument) throws -> Void = { _ in }, declarationValidation: @escaping @Sendable (UIDocument) throws -> Void = { _ in }, semanticValidation: @escaping @Sendable (UIDocument) throws -> Void = { _ in }, finalValidation: @escaping @MainActor @Sendable (UIDocument) throws -> Void = { _ in }) {
    self.requirements = requirements
    self.sourceInputValidation = sourceInputValidation
    self.sourceValidation = sourceValidation
    self.declarationValidation = declarationValidation
    self.semanticValidation = semanticValidation
    self.finalValidation = finalValidation
  }
}
