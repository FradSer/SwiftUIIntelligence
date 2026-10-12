import SwiftUI

/// Embeds in the host's NavigationStack; does not create a second navigation root.
/// This is the shared text → provider → validated JSON → native UI entry point.
public struct GeneratedDocumentView: View {
  @State private var session: DocumentChatSession
  @State private var state = DocumentState()
  @State private var prompt = ""
  private let actions: ActionRegistry
  public init(provider: any DocumentGenerationProvider, actions: ActionRegistry = ActionRegistry([:]), requirements: DocumentRequirements = .init(), semanticValidation: @escaping @Sendable (UIDocument) throws -> Void = { _ in }) {
    self.actions = actions
    _session = State(initialValue: DocumentChatSession(provider: provider, registeredActions: actions.names, requirements: requirements, semanticValidation: semanticValidation))
  }
  public init(session: DocumentChatSession, actions: ActionRegistry, state: DocumentState) {
    _session = State(initialValue: session); self.actions = actions; _state = State(initialValue: state)
  }
  public var body: some View {
    VStack(spacing: 12) {
      if let document = session.document {
        SwiftUIIntelligenceView(document: document, actions: actions, state: state).id(session.revision)
      } else {
        ContentUnavailableView("Describe your interface", systemImage: "text.bubble", description: Text("Ask for a form, plan, comparison or data report."))
      }
      if session.phase == .generating {
        HStack {
          ProgressView()
          Text("Generating · \(session.snapshotCount) snapshots").font(.caption)
          Button("Cancel") { session.cancel() }
        }
      }
      if let error = session.errorMessage {
        Text(error).font(.callout).foregroundStyle(.red)
        if session.canRetry { Button("Retry") { Task { await session.retry() } } }
      }
      if let error = state.errorMessage { Text(error).font(.callout).foregroundStyle(.red) }
      HStack {
        TextField("Describe or revise the UI", text: $prompt, axis: .vertical)
          .lineLimit(1...4).accessibilityIdentifier("generated-prompt")
        Button("Generate") {
          let text = prompt; prompt = ""
          Task { await session.send(text) }
        }
          .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || session.phase == .generating)
          .accessibilityIdentifier("generated-send")
      }.padding()
    }
  }
}
