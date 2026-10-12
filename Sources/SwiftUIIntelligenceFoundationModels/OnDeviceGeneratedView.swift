import SwiftUIIntelligence
import SwiftUI

/// A third-party host supplies text through the composer; Apple inference stays on device.
public struct OnDeviceGeneratedView: View {
  private let actions: ActionRegistry
  public init(actions: ActionRegistry = ActionRegistry([:])) { self.actions = actions }
  public var body: some View {
    GeneratedDocumentView(provider: FoundationModelsDocumentProvider(), actions: actions)
  }
}
