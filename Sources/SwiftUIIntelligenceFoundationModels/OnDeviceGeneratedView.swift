import SwiftUIIntelligence
import SwiftUI

/// A third-party host supplies text through the composer; Apple inference stays on device.
public struct OnDeviceGeneratedView: View {
  private let providerLabel: String
  private let actions: ActionRegistry
  private let calculations: CalculationRegistry?
  private let requirements: DocumentRequirements
  private let sourceInputValidation: (@Sendable (String, String, RecordCollection) throws -> Void)?
  private let sourceValidation: @Sendable (SwiftUIIntelligence.UIDocument) throws -> Void
  private let declarationValidation: @Sendable (SwiftUIIntelligence.UIDocument) throws -> Void
  private let semanticValidation: @Sendable (SwiftUIIntelligence.UIDocument) throws -> Void
  public init(providerLabel: String = "Apple on-device model · \(FoundationModelsDocumentProvider.availabilityDescription)", calculations: CalculationRegistry? = nil, actions: ActionRegistry = ActionRegistry([:]), requirements: DocumentRequirements = .init(), sourceInputValidation: (@Sendable (String, String, RecordCollection) throws -> Void)? = nil, sourceValidation: @escaping @Sendable (SwiftUIIntelligence.UIDocument) throws -> Void = { _ in }, declarationValidation: @escaping @Sendable (SwiftUIIntelligence.UIDocument) throws -> Void = { _ in }, semanticValidation: @escaping @Sendable (SwiftUIIntelligence.UIDocument) throws -> Void = { _ in }) {
    self.providerLabel = providerLabel
    self.actions = actions
    self.calculations = calculations
    self.requirements = requirements
    self.sourceInputValidation = sourceInputValidation
    self.sourceValidation = sourceValidation
    self.declarationValidation = declarationValidation
    self.semanticValidation = semanticValidation
  }
  public var body: some View {
    GeneratedDocumentView(provider: FoundationModelsDocumentProvider(), providerLabel: providerLabel, actions: actions, calculations: calculations, requirements: requirements, sourceInputValidation: sourceInputValidation, sourceValidation: sourceValidation, declarationValidation: declarationValidation, semanticValidation: semanticValidation)
  }
}
