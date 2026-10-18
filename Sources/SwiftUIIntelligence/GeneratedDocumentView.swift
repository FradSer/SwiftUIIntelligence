import SwiftUI

/// Embeds in the host's NavigationStack; does not create a second navigation root.
/// This is the shared text → provider → validated JSON → native UI entry point.
public struct GeneratedDocumentView: View {
  @State private var session: DocumentChatSession
  @State private var state = DocumentState()
  @State private var prompt = ""
  @State private var showsWideChat = false
  @State private var panel: GeneratedDocumentPanel?
  private let actions: ActionRegistry
  private let providerLabel: String
  /// The host supplies this provenance label. It does not come from generated content.
  public init(provider: any DocumentGenerationProvider, providerLabel: String = "Host-supplied provider", actions: ActionRegistry = ActionRegistry([:]), calculations: CalculationRegistry? = nil, requirements: DocumentRequirements = .init(), sourceInputValidation: (@Sendable (String, String, RecordCollection) throws -> Void)? = nil, sourceValidation: @escaping @Sendable (UIDocument) throws -> Void = { _ in }, declarationValidation: @escaping @Sendable (UIDocument) throws -> Void = { _ in }, semanticValidation: @escaping @Sendable (UIDocument) throws -> Void = { _ in }) {
    self.actions = actions
    self.providerLabel = providerLabel
    _session = State(initialValue: Self.makeSession(provider: provider, actions: actions, calculations: calculations, requirements: requirements, sourceInputValidation: sourceInputValidation, sourceValidation: sourceValidation, declarationValidation: declarationValidation, semanticValidation: semanticValidation))
  }

  // Keep session construction testable without inspecting SwiftUI state or evaluating the body.
  static func makeSession(provider: any DocumentGenerationProvider, actions: ActionRegistry = ActionRegistry([:]), calculations: CalculationRegistry? = nil, requirements: DocumentRequirements = .init(), sourceInputValidation: (@Sendable (String, String, RecordCollection) throws -> Void)? = nil, sourceValidation: @escaping @Sendable (UIDocument) throws -> Void = { _ in }, declarationValidation: @escaping @Sendable (UIDocument) throws -> Void = { _ in }, semanticValidation: @escaping @Sendable (UIDocument) throws -> Void = { _ in }) -> DocumentChatSession {
    DocumentChatSession(provider: provider, registeredActions: actions.names, calculations: calculations, requirements: requirements, sourceInputValidation: sourceInputValidation, sourceValidation: sourceValidation, declarationValidation: declarationValidation, semanticValidation: semanticValidation)
  }
  /// The session supplies the calculation registry. Configure calculations when you create the session.
  /// The calculations argument remains for source compatibility and has no effect.
  public init(session: DocumentChatSession, actions: ActionRegistry, state: DocumentState, calculations: CalculationRegistry? = nil, providerLabel: String = "Host-supplied provider") {
    _session = State(initialValue: session); self.actions = actions; _state = State(initialValue: state)
    self.providerLabel = providerLabel
  }
  public var body: some View {
    VStack(spacing: 12) {
      HStack {
        Button("Original") { panel = .original }
          .disabled(session.originalSources.isEmpty)
          .accessibilityIdentifier("generated-original-button")
        Button("Details") { panel = .details }
          .accessibilityIdentifier("generated-details-button")
        Spacer()
        Button("New chat") {
          session.reset()
          state = DocumentState()
          prompt = ""
          showsWideChat = false
          panel = nil
        }
        .accessibilityIdentifier("generated-reset")
      }.padding(.horizontal)
      GeometryReader { geometry in
        HStack(alignment: .top, spacing: 16) {
          if geometry.size.width >= 900, !session.originalSources.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
              HStack {
                Button("Chat") { showsWideChat = true }
                  .accessibilityIdentifier("generated-chat-tab")
                Button("Original") { showsWideChat = false }
                  .accessibilityIdentifier("generated-original-tab")
              }
              ScrollView {
                if showsWideChat {
                  VStack(alignment: .leading, spacing: 16) {
                    ForEach(Array(session.messages.enumerated()), id: \.offset) { index, message in
                      VStack(alignment: .leading, spacing: 6) {
                        Text(message.role.rawValue.capitalized).font(.caption).foregroundStyle(.secondary)
                        Text(message.role == .assistant ? "Accepted document" : message.content)
                          .textSelection(.enabled)
                          .accessibilityIdentifier("generated-chat-message-\(index)")
                      }
                    }
                  }.frame(maxWidth: .infinity, alignment: .leading)
                } else {
                  GeneratedOriginalPassages(sources: session.originalSources)
                }
              }
            }
            .frame(width: min(360, geometry.size.width * 0.35))
          }
          result
        }
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
    .sheet(item: $panel) { selected in
      GeneratedDocumentPanels(panel: selected, sources: session.originalSources,
        providerLabel: providerLabel, revision: session.revision, documentJSON: session.documentJSON)
    }
  }

  private var result: some View {
    VStack(spacing: 12) {
      if session.phase == .generating, !session.previewComponents.isEmpty {
        ScrollView {
          VStack(spacing: 12) {
            ForEach(Array(session.previewComponents.enumerated()), id: \.offset) { _, component in
              DocumentPreviewView(document: component, calculations: session.calculationRegistry, embedded: true)
                .id("\(session.previewAttemptID?.uuidString ?? ""):\(component.root.id)")
            }
          }
        }.accessibilityElement(children: .contain)
          .accessibilityIdentifier("generated-preview-components")
      }
      if let document = session.document {
        SwiftUIIntelligenceView(document: document, actions: actions, state: state, calculations: session.calculationRegistry).id(session.revision)
      } else {
        ContentUnavailableView("Describe your interface", systemImage: "text.bubble", description: Text("Ask for a form, plan, comparison or data report."))
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
