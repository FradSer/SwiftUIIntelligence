@_spi(Testing) import SwiftUIIntelligence
import SwiftUIIntelligenceFoundationModels
import SwiftUIIntelligenceWeatherDemo
import Observation
import SwiftUI
import UIKit

@main struct SwiftUIIntelligenceDemoApp: App {
  var body: some Scene {
    WindowGroup {
      Group {
        if ProcessInfo.processInfo.arguments.contains("--expanded-case") {
          ExpandedScenarioScreen()
        } else if ProcessInfo.processInfo.arguments.contains("--sdk-demo") {
          SDKDemoScreen()
        } else if ProcessInfo.processInfo.arguments.contains("--weather-demo")
          || ProcessInfo.processInfo.arguments.contains("--generic-weather")
          || ProcessInfo.processInfo.arguments.contains("--model-dashboard")
          || ProcessInfo.processInfo.arguments.contains("--show-complete")
          || ProcessInfo.processInfo.arguments.contains("--fixture")
        {
          DemoScreen()
        } else {
          ChatScreen()
        }
      }
      .preferredColorScheme(requestedAppearance)
      .modifier(AccessibilityTestOverride())
    }
  }
  private var requestedAppearance: ColorScheme? {
    let args = ProcessInfo.processInfo.arguments
    guard let index = args.firstIndex(of: "--appearance"), args.indices.contains(index + 1) else {
      return nil
    }
    return args[index + 1] == "light" ? .light : .dark
  }
}

private enum DemoPalette {
  static let muted = Color.secondary
  static let blue = Color.blue
}

private struct DemoScreen: View {
  @State private var host = DemoHost()
  @State private var sourceTab = "Raw Output"
  @State private var phoneTab = "Preview"
  @State private var expanded = false

  var body: some View {
    GeometryReader { geometry in
      let wide = geometry.size.width >= 900
      VStack(spacing: 16) {
        if !wide {
          Group {
            HStack(spacing: 12) {
              ForEach(["Preview", "JSON"], id: \.self) { panel in
                Button {
                  phoneTab = panel
                } label: {
                  Text(panel)
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                
                .accessibilityIdentifier(panel == "JSON" ? "panel-json" : "panel-preview")
                .accessibilityValue(phoneTab == panel ? "Selected" : "")
              }
            }
          }
          .padding(.horizontal, 12)
        }
        Group {
          HStack(spacing: 12) {
            if wide || phoneTab == "JSON" {
              sourcePanel.frame(width: wide ? geometry.size.width * 0.36 : nil)
            }
            if wide || phoneTab == "Preview" { previewPanel }
          }
          .frame(height: wide ? min(geometry.size.height - 150, 530) : nil)
        }
        controls.padding(.bottom, 8)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .padding(.horizontal, wide ? 44 : 12)
      .padding(.vertical, wide ? 32 : 12)
      
    }
    .fullScreenCover(isPresented: $expanded) {
      NavigationStack {
        host.preview
          .padding(12)
          
          .navigationTitle(host.previewTitle).navigationBarTitleDisplayMode(.inline)
          .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { expanded = false } }
          }
      }
    }
    .task { host.startIfNeeded() }
  }

  private var sourcePanel: some View {
    VStack(spacing: 0) {
      HStack(spacing: 4) {
        ForEach(["Raw Output", "Parsed JSON"], id: \.self) { tab in
          Button {
            sourceTab = tab
          } label: {
            Text(tab).frame(minHeight: 44)
          }
          
          .accessibilityIdentifier(tab == "Raw Output" ? "raw-tab" : "json-tab")
        }
        Spacer(minLength: 0)
        Button {
          host.perform("copy")
        } label: {
          Image(systemName: "square.on.square").font(.caption).frame(width: 44, height: 44)
        }
        .accessibilityLabel("Copy JSON")
        .accessibilityIdentifier("copy-json")
      }
      .padding(8)
      ScrollView([.vertical, .horizontal]) {
        Text(sourceTab == "Raw Output" ? host.rawOutput : host.parsedOutput)
          .font(.system(.caption, design: .monospaced))
          .foregroundStyle(.primary).textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .topLeading).padding(14)
          .accessibilityIdentifier("json-source")
      }
    }
    
  }

  private var previewPanel: some View {
    VStack(spacing: 8) {
      HStack(spacing: 8) {
        Text("PREVIEW").font(.caption2).foregroundStyle(
          DemoPalette.muted)
        if host.isPlaying {
          ProgressView().accessibilityIdentifier(
            "replay-progress")
        }
        Spacer()
        Button {
          expanded = true
        } label: {
          Image(systemName: "arrow.up.left.and.arrow.down.right").font(.caption).frame(
            width: 44, height: 44)
        }
        .accessibilityLabel("Expand preview")
        .accessibilityIdentifier("expand-preview")
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 6)
      
      host.preview
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

  }

  private var controls: some View {
    VStack(spacing: 10) {
      Group {
        HStack(spacing: 12) {
          ForEach(host.documentActions) { node in
            Button {
              host.perform(node.action)
            } label: {
              Text(node.title).frame(
                minHeight: 44)
            }
            
            .accessibilityIdentifier(node.id)
          }
        }
      }
      VStack(spacing: 6) {
        Text(host.provenanceLabel).font(.caption2).foregroundStyle(.secondary)
        Text(host.message).font(.caption2).foregroundStyle(.primary)
          .accessibilityIdentifier("action-result")
      }
      .multilineTextAlignment(.center)
      .padding(.horizontal, 16).padding(.vertical, 10)
      
    }
  }
}

/// Launch-only validation seam; no additional product controls or business behavior.
private struct SDKDemoScreen: View {
  @State private var count = 0
  private var data: Data {
    guard let url = Bundle.main.url(forResource: "basic", withExtension: "json"),
      let data = try? Data(contentsOf: url)
    else { return Data("{".utf8) }
    return data
  }
  var body: some View {
    SwiftUIIntelligenceView(
      data: data,
      actions: ActionRegistry([
        "greet": { "Hello from the host app." },
        "increment": {
          count += 1
          return "Host count: \(count)"
        },
      ])
    )
    
  }
}

/// All example routes use the same neutral system background as the SDK.
private struct DemoBackdrop: View {
  var body: some View { SwiftUIIntelligenceBackdrop() }
}

@MainActor @Observable private final class DemoHost {
  var stage: WeatherReplayStage = .empty
  var isPlaying = false
  var message = "Ready to replay the fixed weather example."
  private let fixture: String
  private var snapshots: [Data] = []
  private var weatherActions: [UINode] = []
  private let isErrorFixture: Bool
  private var modelDocument = false
  private var lastModelGroupID: String?
  var previewTitle = "Weather Dashboard"
  var provenanceLabel: String { modelDocument ? "Recorded Apple model output · generated on Mac" : "Fixed JSON replay · No model connected" }
  @ObservationIgnored private var playback: Task<Void, Never>?
  @ObservationIgnored lazy var actions = ActionRegistry([
    "replay": { [weak self] in
      self?.replay()
      return self?.modelDocument == true ? "Replaying recorded Apple JSON (no model request)." : "Replaying fixed JSON (no model request)."
    },
    "pause": { [weak self] in
      self?.pause()
      return "Replay paused."
    },
    "complete": { [weak self] in
      self?.showAll()
      return self?.modelDocument == true ? "All model components rendered." : "All weather components rendered."
    },
    "copy": { [weak self] in
      UIPasteboard.general.string = self?.parsedOutput
      return "JSON copied to clipboard."
    },
  ])

  var snapshot: Data {
    snapshots.isEmpty ? Data(fixture.utf8) : snapshots[stage.rawValue]
  }
  var parsedOutput: String { String(decoding: snapshot, as: UTF8.self) }
  var rawOutput: String {
    let counts = [260, 520, 1_460, 2_160, 2_850, parsedOutput.count, parsedOutput.count]
    return String(parsedOutput.prefix(counts[stage.rawValue]))
  }
  var documentActions: [UINode] {
    weatherActions
  }

  @ViewBuilder var preview: some View {
    if isErrorFixture {
      SwiftUIIntelligenceView(data: snapshot, actions: actions, embedded: true)
    } else if modelDocument {
      SwiftUIIntelligenceView(data: snapshot, actions: actions, scrollTargetID: stage == .finale ? lastModelGroupID : nil).clipped()
    } else if ProcessInfo.processInfo.arguments.contains("--generic-weather"),
      let weather = try? WeatherDocument.decode(snapshot, registeredActions: actions.names),
      let document = try? GenericWeatherReference.document(from: weather, registeredActions: actions.names) {
      SwiftUIIntelligenceView(document: document, actions: actions, scrollTargetID: stage == .finale ? "weather-details" : nil)
        .clipped()
    } else {
      WeatherDemoView(data: snapshot, actions: actions)
    }
  }

  init() {
    let arguments = ProcessInfo.processInfo.arguments
    if let flag = arguments.firstIndex(of: "--fixture"), arguments.indices.contains(flag + 1) {
      let fixtures = [
        "bad-json": "{",
        "unknown-component": #"{"version":1,"root":{"id":"root","type":"webview"}}"#,
        "unknown-action":
          #"{"version":1,"root":{"id":"root","type":"button","title":"Run","action":"shell"}}"#,
      ]
      if let invalid = fixtures[arguments[flag + 1]] {
        fixture = invalid
        isErrorFixture = true
        return
      }
    }
    isErrorFixture = false
    if arguments.contains("--model-dashboard") {
      modelDocument = true
      let name = arguments.contains("--model-service") ? "model-service-document" : "model-weather-document"
      let bytes = Bundle.main.url(forResource: name, withExtension: "json").flatMap { try? Data(contentsOf: $0) } ?? Data("{".utf8)
      fixture = String(decoding: bytes, as: UTF8.self)
      do {
        let document = try UIDocument.decode(bytes, registeredActions: [])
        lastModelGroupID = document.root.children.last?.id
        previewTitle = document.root.children.first?.title ?? "Model dashboard"
        let object = try JSONSerialization.jsonObject(with: bytes) as! [String: Any]
        let root = object["root"] as! [String: Any]
        let groups = root["children"] as? [[String: Any]] ?? []
        snapshots = try WeatherReplayStage.allCases.map { stage in
          if stage == .details || stage == .finale { return bytes }
          var partial = object
          var partialRoot = root
          let count = stage == .empty ? 0 : max(1, groups.count * stage.rawValue / 5)
          partialRoot["children"] = Array(groups.prefix(count))
          partial["root"] = partialRoot
          return try JSONSerialization.data(withJSONObject: partial, options: [.sortedKeys])
        }
        let controls = #"{"version":1,"root":{"id":"controls","type":"vstack","spacing":12,"children":[]},"floatingActions":[{"id":"replay-button","type":"button","title":"Replay","action":"replay"},{"id":"pause-button","type":"button","title":"Pause","action":"pause"},{"id":"complete-button","type":"button","title":"Show all","action":"complete"}]}"#
        weatherActions = try UIDocument.decode(Data(controls.utf8), registeredActions: ["replay", "pause", "complete"]).floatingActions
        message = "Ready to replay recorded Apple model output."
        if arguments.contains("--show-complete") { stage = .details }
      } catch { message = "Model recording validation failed: \(error.localizedDescription)" }
      return
    }
    if let url = Bundle.main.url(forResource: "sample", withExtension: "json"),
      let data = try? Data(contentsOf: url)
    {
      fixture = String(decoding: data, as: UTF8.self)
    } else {
      fixture = "{"
    }
    do {
      let names: Set<String> = ["replay", "pause", "complete", "copy"]
      let document = try WeatherDocument.decode(Data(fixture.utf8), registeredActions: names)
      snapshots = try WeatherReplayStage.allCases.map {
        try document.snapshot(at: $0, registeredActions: names)
      }
      weatherActions = document.floatingActions
    } catch {
      message = "Fixture validation failed: \(error.localizedDescription)"
    }
    if arguments.contains("--show-complete") { stage = .details }
  }

  func startIfNeeded() { if stage == .empty && !isErrorFixture && !snapshots.isEmpty { replay() } }
  func perform(_ name: String) {
    do { message = try actions.perform(name) } catch { message = error.localizedDescription }
  }
  private func replay() {
    playback?.cancel()
    stage = .empty
    isPlaying = true
    playback = Task { [weak self] in
      for next in WeatherReplayStage.allCases.dropFirst() {
        do { try await Task.sleep(for: .seconds(3)) } catch { return }
        guard let self else { return }
        self.stage = next
      }
      self?.isPlaying = false
      self?.message = self?.modelDocument == true ? "Recorded Apple JSON replay complete." : "Fixed JSON replay complete."
    }
  }
  private func pause() {
    playback?.cancel()
    isPlaying = false
  }
  private func showAll() {
    pause()
    stage = .details
  }
}

/// The product path is chat → provider → strict JSON → generic native document.
private struct ChatScreen: View {
  @State private var session: DocumentChatSession
  @State private var modeLabel: String
  @State private var input = ""
  @State private var panel = "Chat"
  @State private var sourceShown = false
  @State private var hostResult = ""
  @FocusState private var composerFocused: Bool

  init() {
    let args = ProcessInfo.processInfo.arguments
    let provider: any DocumentGenerationProvider
    let label: String
    if args.contains("--chat-rich-output") {
      provider = RecordedRichProvider()
      label = "Recorded Apple model output · generated on Mac · rich components"
    } else if args.contains("--chat-real-outputs") {
      provider = RecordedModelProvider()
      label = "Recorded Apple model output · generated on Mac"
    } else if let i = args.firstIndex(of: "--chat-fixture") {
      provider = SyntheticChatProvider(failure: args.indices.contains(i + 1) ? args[i + 1] : "none")
      label = "Synthetic provider · not AI generation"
    } else {
      provider = FoundationModelsDocumentProvider()
      label = "Apple on-device model · \(FoundationModelsDocumentProvider.availabilityDescription)"
    }
    _session = State(
      initialValue: DocumentChatSession(provider: provider, registeredActions: ["acknowledge"]))
    _modeLabel = State(initialValue: label)
  }

  var body: some View {
    GeometryReader { geometry in
      let wide = geometry.size.width >= 900
      VStack(spacing: 12) {
        header
        if !wide {
          Group {
            HStack(spacing: 10) {
              ForEach(["Chat", "Document"], id: \.self) { value in
                Button {
                  panel = value
                } label: {
                  Text(value).frame(maxWidth: .infinity, minHeight: 44)
                }
                
                .accessibilityIdentifier(value == "Chat" ? "chat-panel" : "document-panel")
              }
            }
          }
        }
        if session.phase == .generating {
          HStack {
            ProgressView().accessibilityIdentifier("chat-loading-indicator")
            Text("Generating a document…").font(.callout)
            Spacer()
          }
          .padding(14)

        }
        if session.phase == .failed { failure }
        if !hostResult.isEmpty {
          Text(hostResult).font(.callout).padding(14).frame(maxWidth: .infinity)
            .accessibilityIdentifier(
              "chat-action-result")
        }
        Group {
          HStack(alignment: .top, spacing: 16) {
            if wide || panel == "Chat" {
              conversation.frame(maxWidth: wide ? geometry.size.width * 0.34 : .infinity)
            }
            if wide || panel == "Document" { documentPanel }
          }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
        composer.padding(.top, 4).padding(.bottom, 8)
      }
      .padding(.horizontal, wide ? 28 : 16).padding(.top, 12)
      
    }
    .onChange(of: session.revision) { _, _ in hostResult = "" }
    .sheet(isPresented: $sourceShown) {
      NavigationStack {
        ScrollView([.vertical, .horizontal]) {
          Text(String(decoding: session.documentJSON ?? Data(), as: UTF8.self))
            .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
            .padding(20).padding(16)
            .accessibilityIdentifier("chat-json-source")
        }
        
        .navigationTitle("Document JSON").navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .confirmationAction) { Button("Done") { sourceShown = false } }
          ToolbarItem(placement: .topBarLeading) {
            Button("Copy") {
              UIPasteboard.general.string = String(
                decoding: session.documentJSON ?? Data(), as: UTF8.self)
            }
          }
        }
      }
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        VStack(alignment: .leading, spacing: 4) {
          Text("SwiftUIIntelligence").font(.title2)
          Text(modeLabel).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier(
            "chat-provider-label")
        }
        Spacer(minLength: 8)
        Button("New chat") {
          session.reset()
          hostResult = ""
          panel = "Chat"
        }
        .accessibilityIdentifier("chat-reset")
      }
      if modeLabel.contains("Unavailable") {
        Button("Try synthetic demo") {
          session = DocumentChatSession(
            provider: SyntheticChatProvider(), registeredActions: ["acknowledge"])
          modeLabel = "Synthetic provider · not AI generation"
        }.accessibilityIdentifier("chat-use-synthetic")
      }
    }
    .padding(14)
  }

  private var conversation: some View {
    ScrollViewReader { proxy in
      ScrollView {
        Group {
          VStack(alignment: .leading, spacing: 12) {
            if session.messages.isEmpty {
              VStack(alignment: .leading, spacing: 10) {
                Text("Start with an idea").font(.headline)
                Text(
                  "Ask for a plan, a handover, a comparison or another document. Follow up to revise it."
                ).font(.callout)
              }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                
                .accessibilityIdentifier("chat-empty")
            }
            ForEach(Array(session.messages.enumerated()), id: \.offset) { index, message in
              VStack(alignment: .leading, spacing: 6) {
                Text(message.role == .user ? "You" : "Document").font(.caption.bold())
                  .foregroundStyle(.secondary)
                Text(message.role == .user ? message.content : "Document \(index / 2 + 1) ready.")
                  .font(.callout).textSelection(.enabled)
              }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .id(index)
            }
          }.padding(.vertical, 4)
        }
      }.accessibilityIdentifier("chat-transcript")
        .onChange(of: session.messages.count) { _, count in
          if count > 0 { proxy.scrollTo(count - 1, anchor: .bottom) }
        }
    }
  }

  private var documentPanel: some View {
    VStack(spacing: 12) {
      HStack {
        Text(session.revision == 0 ? "DOCUMENT" : "DOCUMENT · \(session.revision)").font(
          .caption.bold()
        )
        .accessibilityIdentifier("chat-revision")
        Spacer()
        Button("JSON") { sourceShown = true }.disabled(session.document == nil)
          .accessibilityIdentifier("chat-show-json")
      }.padding(12)
      ScrollView {
        if let document = session.document {
          SwiftUIIntelligenceView(
            document: document,
            actions: ActionRegistry([
              "acknowledge": {
                hostResult = "Host acknowledged the document."
                return hostResult
              }
            ]), embedded: true
          )
          .id(session.revision).frame(maxWidth: .infinity, alignment: .leading)
        } else {
          ContentUnavailableView(
            "Your document appears here", systemImage: "doc.text",
            description: Text("Only validated, complete JSON is rendered.")
          )
          
        }
      }.accessibilityIdentifier("chat-document-scroll")
    }.frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var failure: some View {
    HStack(alignment: .top, spacing: 12) {
      VStack(alignment: .leading, spacing: 6) {
        Text(
          session.failureKind == .invalidDocument
            ? "Response could not be rendered" : "Generation did not finish"
        ).font(.headline)
        Text(session.errorMessage ?? "Try again.").font(.caption).accessibilityIdentifier(
          "chat-error")
        if session.document != nil {
          Text("The previous document is still available.").font(.caption)
        }
      }
      Spacer(minLength: 0)
      if session.canRetry {
        Button("Retry") {
          Task {
            await session.retry()
            if session.phase == .ready { panel = "Document" }
          }
        }
        .accessibilityIdentifier("chat-retry")
      }
    }.padding(14)
  }

  private var composer: some View {
    HStack(alignment: .bottom, spacing: 10) {
      TextField("Ask or revise your document", text: $input, axis: .vertical).lineLimit(1...3)
        .focused($composerFocused)
        .accessibilityIdentifier("chat-input")
      Button {
        let message = input
        input = ""
        composerFocused = false
        Task {
          await session.send(message)
          if session.phase == .ready { panel = "Document" }
        }
      } label: {
        Image(systemName: "arrow.up").font(.headline).frame(width: 44, height: 44)
      }
      .accessibilityLabel("Send").accessibilityIdentifier("chat-send")
      .disabled(
        input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          || session.phase == .generating)
    }
  }
}

/// Explicit deterministic fixtures; they neither inspect keywords nor claim model inference.
private actor SyntheticChatProvider: DocumentGenerationProvider {
  private var count = 0
  private let failure: String
  init(failure: String = "none") { self.failure = failure }
  func generate(_ request: DocumentGenerationRequest) async throws -> Data {
    count += 1
    try await Task.sleep(for: .milliseconds(failure == "slow" ? 6000 : 400))
    if count == 1 {
      if failure == "provider" { throw UIError("Synthetic provider failure. Retry is safe.") }
      if failure == "malformed" { return Data("{".utf8) }
      if failure == "unknown" {
        return Data(#"{"version":1,"root":{"id":"r","type":"webview"}}"#.utf8)
      }
    }
    let number = ["provider", "malformed", "unknown"].contains(failure) ? count - 1 : count
    return Data((number == 1 ? Self.plan : Self.handover).utf8)
  }
  private static let plan =
    #"{"version":1,"root":{"id":"plan","type":"vstack","spacing":16,"children":[{"id":"title","type":"text","text":"Library volunteer plan","style":"title"},{"id":"prep","type":"section","title":"Preparation","children":[{"id":"tasks","type":"list","items":["Set up the welcome desk","Sort the returned books","Review the shift handover"]}],"spacing":12},{"id":"shifts","type":"section","title":"Saturday shifts","spacing":12,"children":[{"id":"table","type":"table","columns":["Task","Time"],"rows":[["Welcome desk","10am"],["Book sorting","2pm"]]}]},{"id":"note","type":"callout","text":"Synthetic fixture for interaction testing.","tone":"note"},{"id":"ack","type":"button","title":"Acknowledge","action":"acknowledge"}]},"floatingActions":[]}"#
  private static let handover =
    #"{"version":1,"root":{"id":"release","type":"vstack","spacing":16,"children":[{"id":"release-title","type":"text","text":"Offline notes release handover","style":"title"},{"id":"checks","type":"section","title":"Verification","spacing":12,"children":[{"id":"checklist","type":"list","items":["Check offline save and restore","Verify export in a clean install"]}]},{"id":"pending","type":"callout","text":"Export testing is pending.","tone":"warning"}]},"floatingActions":[]}"#
}

/// Replays unchanged JSON actually generated by the Mac model; no inference on simulator.
private actor RecordedModelProvider: DocumentGenerationProvider {
  private var index = 0
  func generate(_ request: DocumentGenerationRequest) async throws -> Data {
    index += 1
    guard index <= 3,
      let url = Bundle.main.url(forResource: "model-document-\(index)", withExtension: "json")
    else { throw UIError("Recorded model response is not bundled for this turn.") }
    return try Data(contentsOf: url)
  }
}

private struct RecordedRichProvider: DocumentGenerationProvider {
  func generate(_ request: DocumentGenerationRequest) async throws -> Data {
    guard let url = Bundle.main.url(forResource: "model-rich-document", withExtension: "json") else {
      throw UIError("Recorded rich model response is not bundled.")
    }
    return try Data(contentsOf: url)
  }
}

/// Saved, unchanged real model outputs enter through the SAME public session API.
private struct ExpandedScenarioProvider: DocumentGenerationProvider {
  let name: String
  func generate(_ request: DocumentGenerationRequest) async throws -> Data {
    guard let url = Bundle.main.url(forResource: "expanded-" + name, withExtension: "json") else { throw UIError("Missing validated model recording.") }
    return try Data(contentsOf: url)
  }
}
private struct ExpandedScenarioScreen: View {
  @State private var session: DocumentChatSession
  @State private var state = DocumentState()
  private let prompt: String
  init() {
    let args = ProcessInfo.processInfo.arguments
    let index = args.firstIndex(of: "--expanded-case")!
    let name = args.indices.contains(index + 1) ? args[index + 1] : "settings"
    prompt = Bundle.main.url(forResource: "expanded-" + name, withExtension: "txt").flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? "Missing recorded prompt"
    _session = State(initialValue: DocumentChatSession(provider: ExpandedScenarioProvider(name: name), registeredActions: name == "settings" ? ["submit"] : []))
  }
  var body: some View {
    NavigationStack {
      VStack(spacing: 8) {
        Text("Recorded Apple model output · generated on Mac").font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("expanded-mode")
        GeneratedDocumentView(session: session, actions: ActionRegistry(async: ["submit": { event in
          let edited = event.state.values.contains(.text("Edited"))
          let enabled = event.state.values.contains(.boolean(true))
          return "Host received edited=\(edited), reminders=\(enabled)."
        }]), state: state)
      }
    }.task { await session.send(prompt) }
  }
}

private struct AccessibilityTestOverride: ViewModifier {
  @ViewBuilder func body(content: Content) -> some View {
    if ProcessInfo.processInfo.arguments.contains("--test-reduce-transparency") {
      content.environment(\.swiftUIIntelligenceTestReduceTransparency, true)
    } else {
      content
    }
  }
}
