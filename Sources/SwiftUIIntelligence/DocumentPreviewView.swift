import SwiftUI

/// A read-only view of one generated component, not the final document tree.
///
/// Pass the validated `DocumentChatSession.preview` document. The embedded renderer
/// validates it again against inert action IDs and the supplied calculation registry.
/// This view never accepts host actions or the accepted document's state. Calculations
/// must be pure, as required by `CalculationRegistry`; they can run to prepare output.
///
/// Controls and navigation links are disabled. With embedded=false, this view supplies an enabled scroll view.
/// With embedded=true, the parent owns scrolling; the component remains read-only.
/// Floating actions are validated but are not displayed by the embedded renderer.
@MainActor public struct DocumentPreviewView: View {
  private let embedded: Bool
  private let document: UIDocument
  private let calculations: CalculationRegistry?
  private let actions: ActionRegistry
  @State private var previewState = DocumentState()

  /// Creates an isolated preview. Change the view identity to start a new preview lifetime.
  public init(document: UIDocument, calculations: CalculationRegistry? = nil, embedded: Bool = false) {
    self.embedded = embedded
    self.document = document
    self.calculations = calculations
    var callbacks: [String: @MainActor () throws -> String] = [:]
    func collect(_ node: UINode) {
      if node.type == .button {
        callbacks[node.action] = {
          throw UIError("Actions are unavailable in a read-only preview.")
        }
      }
      node.children.forEach(collect)
    }
    collect(document.root)
    document.floatingActions.forEach(collect)
    actions = ActionRegistry(callbacks)
  }

  private var component: some View {
    SwiftUIIntelligenceView(document: document, actions: actions, embedded: true,
      state: previewState, calculations: calculations)
      .disabled(true)
      .padding(.horizontal, 20)
      .padding(.vertical, 24)
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Generating preview")
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 20)
        .accessibilityIdentifier("document-preview-status")
      if embedded { component }
      else {
        ScrollView { component }
          .accessibilityIdentifier("document-preview-scroll")
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("document-preview")
  }
}
