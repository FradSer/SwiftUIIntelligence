@_spi(Testing) import SwiftUIIntelligence
import SwiftUIIntelligenceFoundationModels
import SwiftUIIntelligenceExamples
import SwiftUIIntelligenceWeatherDemo
import Observation
import SwiftUI
import UIKit

@main struct SwiftUIIntelligenceDemoApp: App {
  var body: some Scene {
    WindowGroup {
      Group {
        if ProcessInfo.processInfo.arguments.contains("--progressive-preview-failure") {
          ProgressivePreviewScreen(allowsCompletion: true, failsCompletion: true)
        } else if ProcessInfo.processInfo.arguments.contains("--progressive-preview-final") {
          ProgressivePreviewScreen(allowsCompletion: true)
        } else if ProcessInfo.processInfo.arguments.contains("--progressive-preview") {
          ProgressivePreviewScreen()
        } else if ProcessInfo.processInfo.arguments.contains("--public-wrapper-fixture") {
          NavigationStack {
            GeneratedDocumentView(provider: PublicWrapperFixtureProvider())
          }
        } else if ProcessInfo.processInfo.arguments.contains("--wrapper-registry") {
          WrapperRegistryScreen()
        } else if ProcessInfo.processInfo.arguments.contains("--record-editing") {
          RecordEditingScreen()
        } else if ProcessInfo.processInfo.arguments.contains("--calculation-lifecycle") {
          CalculationLifecycleScreen()
        } else if ProcessInfo.processInfo.arguments.contains("--expanded-case") {
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

/// Synthetic responses for the public wrapper's source/metadata regression only.
private actor PublicWrapperFixtureProvider: DocumentGenerationProvider {
  private var count = 0
  func generate(_ request: DocumentGenerationRequest) async throws -> Data {
    count += 1
    if count == 2 { throw UIError("Synthetic wrapper failure") }
    return Data(#"{"version":1,"root":{"id":"wrapper-result","type":"text","text":"Synthetic public wrapper result"}}"#.utf8)
  }
}

/// Synthetic native harness. This route never calls a model or an external service.
private struct ProgressivePreviewScreen: View {
  @State private var provider: SyntheticProgressivePreviewProvider
  @State private var session: DocumentChatSession
  @State private var state = DocumentState()
  @State private var actionCount = 0
  @State private var hostError: String?
  private let allowsCompletion: Bool

  init(allowsCompletion: Bool = false, failsCompletion: Bool = false) {
    let provider = SyntheticProgressivePreviewProvider(allowsCompletion: allowsCompletion, failsCompletion: failsCompletion)
    _provider = State(initialValue: provider)
    _session = State(initialValue: DocumentChatSession(
      provider: provider, registeredActions: ["submit"]))
    self.allowsCompletion = allowsCompletion
  }

  var body: some View {
    VStack(spacing: 12) {
      Text("Synthetic progressive preview")
      Text("Host actions: \(actionCount)")
      Text("Host state: \(hostInput)")
      if let hostError { Text(hostError) }
      HStack {
        Button("Edit accepted") {
          do { try state.set("input", to: .number(3)) }
          catch { hostError = error.localizedDescription }
        }.disabled(session.phase != .ready)
        Button("Begin preview") {
          Task { await session.send("Show a synthetic read-only preview") }
        }.disabled(session.phase != .ready)
      }
      if allowsCompletion && session.phase == .generating && session.preview != nil {
        Button("Complete generation") {
          Task { await provider.finish() }
        }
      }
      GeneratedDocumentView(session: session, actions: ActionRegistry([
        "submit": {
          actionCount += 1
          return "Host action dispatched"
        }
      ]), state: state)
    }
    .padding()
    .task { await session.send("Load the synthetic accepted document") }
    .onDisappear { session.cancel() }
  }

  private var hostInput: String {
    guard case .number(let input) = state.values["input"] else { return "unloaded" }
    return String(Int(input))
  }
}

private actor SyntheticProgressivePreviewProvider: ProgressiveDocumentGenerationProvider {
  private var requestCount = 0
  private let allowsCompletion: Bool
  private let failsCompletion: Bool
  private struct Attempt {
    let id: UUID
    var completion: CheckedContinuation<Void, Error>?
    var finished = false
    var cancelled = false
  }
  private var currentAttempt: Attempt?

  init(allowsCompletion: Bool = false, failsCompletion: Bool = false) {
    self.allowsCompletion = allowsCompletion
    self.failsCompletion = failsCompletion
  }

  func finish() {
    guard currentAttempt != nil else { return }
    currentAttempt?.finished = true
    let completion = currentAttempt?.completion
    currentAttempt?.completion = nil
    completion?.resume()
  }

  private func cancelCompletion(attemptID: UUID) {
    guard currentAttempt?.id == attemptID else { return }
    currentAttempt?.cancelled = true
    let completion = currentAttempt?.completion
    currentAttempt?.completion = nil
    completion?.resume(throwing: CancellationError())
  }

  private static let final = #"{"version":1,"state":[{"id":"input","kind":"number","value":2}],"root":{"id":"final-root","type":"vstack","children":[{"id":"final-text","type":"text","text":"Final accepted"},{"id":"final-input","type":"control","title":"Final input","binding":"input","controlType":"stepper"},{"id":"final-submit","type":"button","title":"Submit final","action":"submit"}]}}"#
  private static let accepted = #"{"version":1,"state":[{"id":"input","kind":"number","value":2}],"root":{"id":"accepted-root","type":"vstack","children":[{"id":"accepted-text","type":"text","text":"Prior accepted"},{"id":"accepted-input","type":"control","title":"Accepted input","binding":"input","controlType":"stepper"}]}}"#
  private static let preview = #"{"version":1,"state":[{"id":"input","kind":"number","value":2}],"root":{"id":"preview-section","type":"section","title":"Synthetic preview component","children":[{"id":"preview-text","type":"text","text":"Preview visible"},{"id":"preview-input","type":"control","title":"Preview input","binding":"input","controlType":"stepper"},{"id":"preview-submit","type":"button","title":"Preview submit","action":"submit"}]}}"#

  func generate(_ request: DocumentGenerationRequest) async throws -> Data {
    try await generate(request, onPreviewEvent: { _ in })
  }

  func generate(_ request: DocumentGenerationRequest,
    onPreviewEvent: @escaping @Sendable (DocumentPreviewEvent) async -> Void
  ) async throws -> Data {
    requestCount += 1
    if requestCount == 1 { return Data(Self.accepted.utf8) }
    let attemptID = UUID()
    // Superseding an attempt must also release its pending completion gate.
    let supersededCompletion = currentAttempt?.completion
    currentAttempt = Attempt(id: attemptID)
    supersededCompletion?.resume(throwing: CancellationError())
    await onPreviewEvent(.begin(attemptID: attemptID))
    await onPreviewEvent(.component(.init(attemptID: attemptID, sequence: 1,
      data: Data(Self.preview.utf8))))
    let second = #"{"version":1,"state":[{"id":"input","kind":"number","value":2}],"root":{"id":"second-preview","type":"text","text":"Second complete component"}}"#
    await onPreviewEvent(.component(.init(attemptID: attemptID, sequence: 2, data: Data(second.utf8))))
    if allowsCompletion {
      try await withTaskCancellationHandler {
        try Task.checkCancellation()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
          guard let attempt = currentAttempt, attempt.id == attemptID else {
            continuation.resume(throwing: CancellationError())
            return
          }
          if attempt.cancelled { continuation.resume(throwing: CancellationError()) }
          else if attempt.finished { continuation.resume() }
          else { currentAttempt?.completion = continuation }
        }
        try Task.checkCancellation()
      } onCancel: {
        Task { await self.cancelCompletion(attemptID: attemptID) }
      }
      if failsCompletion { throw UIError("Synthetic generation failed.") }
      return Data(Self.final.utf8)
    }
    // Keep the component provisional. Cancellation must never produce a final document.
    try await Task.sleep(for: .seconds(60))
    throw CancellationError()
  }
}

/// Synthetic chat-only preview fixture. Never calls a model or external service.
private actor ChatProgressiveFixtureProvider: ProgressiveDocumentGenerationProvider {
  static let shared = ChatProgressiveFixtureProvider()
  private var advanceRequested = false
  private var activeAttempt: UUID?
  private var continuation: CheckedContinuation<Void, Never>?
  func advance() {
    advanceRequested = true
    continuation?.resume(); continuation = nil
  }
  private func releaseCancelledWait(attempt: UUID) {
    guard activeAttempt == attempt else { return }
    continuation?.resume(); continuation = nil
  }
  func generate(_ request: DocumentGenerationRequest) async throws -> Data {
    try await generate(request, onPreviewEvent: { _ in })
  }
  func generate(_ request: DocumentGenerationRequest, onPreviewEvent: @escaping @Sendable (DocumentPreviewEvent) async -> Void) async throws -> Data {
    let attempt = UUID()
    continuation?.resume(); continuation = nil
    activeAttempt = attempt
    advanceRequested = false
    let data = Data(#"{"version":1,"root":{"id":"chat-preview","type":"text","text":"Chat provisional component"}}"#.utf8)
    await onPreviewEvent(.begin(attemptID: attempt))
    await onPreviewEvent(.component(.init(attemptID: attempt, sequence: 1, data: data)))
    try await withTaskCancellationHandler {
      try Task.checkCancellation()
      await withCheckedContinuation { continuation in
        if advanceRequested || Task.isCancelled { continuation.resume() } else { self.continuation = continuation }
      }
      try Task.checkCancellation()
    } onCancel: {
      Task { await self.releaseCancelledWait(attempt: attempt) }
    }
    try Task.checkCancellation()
    let retry = UUID()
    await onPreviewEvent(.begin(attemptID: retry))
    let next = Data(#"{"version":1,"root":{"id":"chat-retry","type":"text","text":"Retried provisional component"}}"#.utf8)
    await onPreviewEvent(.component(.init(attemptID: retry, sequence: 1, data: next)))
    try await Task.sleep(for: .seconds(60))
    throw CancellationError()
  }
}

private struct WrapperRegistryScreen: View {
  @State private var registry = makeRegistry(multiplier: 2)
  var body: some View {
    VStack {
      Text("Synthetic public wrapper lifecycle")
      GeneratedDocumentView(provider: ChatResponseProvider { _ in
        #"{"version":1,"state":[{"id":"input","kind":"number","value":2},{"id":"output","kind":"text","value":"Pending"}],"calculations":[{"id":"scale","capability":"scale","inputs":{"input":"input"},"outputs":{"output":"output"}}],"root":{"id":"root","type":"vstack","children":[{"id":"input-control","type":"control","title":"Input","binding":"input","controlType":"stepper"},{"id":"result","type":"text","text":"Pending","binding":"output"}]}}"#
      }, calculations: registry)
      Button("Replace parent registry") { registry = Self.makeRegistry(multiplier: 3) }
    }
  }
  private static func makeRegistry(multiplier: Double) -> CalculationRegistry {
    try! CalculationRegistry([
      .init(id: "scale", inputs: ["input": .number], outputs: ["output": .text]) { values in
        guard case .number(let input) = values["input"] else { throw UIError("Invalid input.") }
        return ["output": .text("Session result: \(Int(input * multiplier))")]
      }
    ])
  }
}

private struct RecordEditingScreen: View {
  @State private var state = DocumentState()
  @State private var registry = makeRegistry()
  private static let json = #"{"version":1,"state":[{"id":"total","kind":"text","value":"Pending"},{"id":"numericTotal","kind":"number","value":0,"maximum":10000}],"records":[{"id":"items","schema":{"fields":{"name":"text","amount":"number","included":"boolean"}},"rows":[{"id":"tea","values":{"name":"Tea","amount":125,"included":true}}]}],"calculations":[{"id":"sum","capability":"sum","inputs":{},"outputs":{"total":"total","numeric":"numericTotal"},"recordInputs":{"items":"items"}}],"root":{"id":"root","type":"vstack","children":[{"id":"intro","type":"text","text":"Synthetic record editing test"},{"id":"items-table","type":"table","columns":["Item","Amount","Included"],"rows":[["Pending","Pending","Pending"]],"recordSource":"items","recordFields":["name","amount","included"],"editableFields":["amount","included"]},{"id":"total-output","type":"text","text":"Pending","binding":"total"},{"id":"total-metric","type":"metric","label":"Total minor units","value":"Pending","valueBinding":"numericTotal","detail":"Synthetic exact numeric result","icon":"money"}]}}"#
  var body: some View {
    SwiftUIIntelligenceView(data: Data(Self.json.utf8), actions: ActionRegistry([:]), state: state, calculations: registry)
  }
  private static func makeRegistry() -> CalculationRegistry {
    try! CalculationRegistry([
      .init(id: "sum", inputs: [:], outputs: ["total": .text, "numeric": .number],
        recordInputs: ["items": .init(fields: ["name": .text, "amount": .number, "included": .boolean])], recordOutputs: [:]) { _, records in
        var total = 0.0
        for row in records["items"]! {
          guard case .number(let amount) = row.values["amount"], amount >= 0,
            case .boolean(let included) = row.values["included"] else { throw UIError("Amount must be nonnegative.") }
          if included { total += amount }
        }
        return CalculationResult(values: ["total": .text("Total: \(Int(total))"), "numeric": .number(total)])
      }
    ])
  }
}

/// Synthetic host used only to verify registry and state replacement.
private struct CalculationLifecycleScreen: View {
  @State private var state = DocumentState()
  @State private var registry = makeRegistry(multiplier: 2)
  @State private var invalidReplacement = false
  private static let documentJSON = #"{"version":1,"state":[{"id":"people","kind":"number","value":2},{"id":"quantity","kind":"text","value":"Pending"},{"id":"chartAmount","kind":"number","value":1}],"calculations":[{"id":"scale","capability":"scale","inputs":{"people":"people"},"outputs":{"quantity":"quantity","amount":"chartAmount"},"recordOutputs":{"items":"items","events":"events"}}],"root":{"id":"root","type":"vstack","children":[{"id":"input","type":"control","title":"People","binding":"people","controlType":"stepper"},{"id":"output","type":"text","text":"Pending","binding":"quantity"},{"id":"reactive-chart","type":"chart","title":"Calculated amount","chartStyle":"donut","points":[{"label":"Amount","series":"Total","value":1,"binding":"chartAmount"}]},{"id":"reactive-timeline","type":"timeline","title":"Calculated timeline","events":[{"time":"18:30","title":"Prepare portions","detail":"Pending"}],"recordSource":"events","recordFields":["time","title","detail"]},{"id":"items-table","type":"table","columns":["Item","Amount"],"rows":[["Pending","Pending"]],"recordSource":"items","recordFields":["name","amount"]},{"id":"items-list","type":"list","items":["Pending"],"recordSource":"items","recordFields":["name"]},{"id":"record-chart","type":"chart","title":"Filtered comparison","chartStyle":"bar","points":[{"label":"Pending","value":1,"series":"Price"}],"recordSource":"items","recordFields":["name","amount","name"]}]}}"#
  var body: some View {
    VStack {
      Text("Synthetic calculation lifecycle test")
      SwiftUIIntelligenceView(data: Data((invalidReplacement ? Self.documentJSON.replacingOccurrences(of: "\"chartStyle\":\"donut\"", with: "\"chartStyle\":\"radar\"").replacingOccurrences(of: "\"points\":[", with: "\"points\":[{\"label\":\"Second\",\"series\":\"Total\",\"value\":1},{\"label\":\"Third\",\"series\":\"Total\",\"value\":1},") : Self.documentJSON).utf8), actions: ActionRegistry([:]), state: state, calculations: registry)
      Button("Replace registry") { registry = Self.makeRegistry(multiplier: 3) }
      Button("Replace state") { state = DocumentState() }
      Button("Empty chart") { registry = Self.makeEmptyRegistry() }
      Button("Invalid replacement") {
        registry = Self.makeRegistry(multiplier: 60)
        invalidReplacement = true
      }
    }
  }
  private static func makeEmptyRegistry() -> CalculationRegistry {
    try! CalculationRegistry([
      .init(id: "scale", inputs: ["people": .number], outputs: ["quantity": .text, "amount": .number],
        recordOutputs: ["items": .init(fields: ["name": .text, "amount": .number]),
          "events": .init(fields: ["time": .text, "title": .text, "detail": .text])]) { _ in
        CalculationResult(values: ["quantity": .text("Empty result"), "amount": .number(1)], records: ["items": [], "events": []])
      }
    ])
  }

  private static func makeRegistry(multiplier: Double) -> CalculationRegistry {
    try! CalculationRegistry([
      .init(id: "scale", inputs: ["people": .number], outputs: ["quantity": .text, "amount": .number],
        recordOutputs: ["items": .init(fields: ["name": .text, "amount": .number]),
          "events": .init(fields: ["time": .text, "title": .text, "detail": .text])]) { input in
        guard case .number(let people) = input["people"] else { throw UIError("Invalid people value.") }
        return CalculationResult(values: ["quantity": .text("Derived value: \(Int(people * multiplier))"), "amount": .number(people * multiplier)],
          records: ["items": [.init(id: "sample", values: ["name": .text("Synthetic item"), "amount": .number(people * multiplier)])],
            "events": [.init(id: "prepare", values: ["time": .text("18:30"), "title": .text("Prepare portions"),
              "detail": .text("Derived value: \(Int(people * multiplier))")])]])
      }
    ])
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
      SwiftUIIntelligenceView(data: snapshot, actions: actions, scrollTargetID: stage == .finale ? lastModelGroupID : nil)
    } else if ProcessInfo.processInfo.arguments.contains("--generic-weather"),
      let weather = try? WeatherDocument.decode(snapshot, registeredActions: actions.names),
      let document = try? GenericWeatherReference.document(from: weather, registeredActions: actions.names) {
      SwiftUIIntelligenceView(document: document, actions: actions, scrollTargetID: stage == .finale ? "weather-details" : nil)

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

/// Explicit host metadata. User text never selects an acceptance policy.
private enum InteractiveExample: String, CaseIterable {
  case equipment = "Equipment comparison"
  case meal = "Meal plan"
  case bill = "Split bill"

  var prompt: String {
    switch self {
    case .equipment: ExampleRequests.equipment
    case .meal: ExampleRequests.meal
    case .bill: ExampleRequests.bill
    }
  }

  @MainActor func policy(registry: CalculationRegistry) -> DocumentValidationPolicy {
    let example: ExampleAcceptance.Example = switch self {
    case .equipment: .equipment
    case .meal: .meal
    case .bill: .bill
    }
    let requirements: DocumentRequirements = switch self {
    case .meal: .init(components: [.table, .timeline], controls: [.stepper, .datePicker], stateCount: 3, stateKinds: [.number, .date], projectedComponents: [.table, .timeline])
    case .bill: .init(components: [.metric, .table], controls: [.stepper], projectedComponents: [.table])
    case .equipment: .init(components: [.table, .chart], projectedComponents: [.table, .chart])
    }
    return DocumentValidationPolicy(requirements: requirements,
      sourceInputValidation: { try ExampleAcceptance.validateSourceInput(capability: $0, input: $1, collection: $2, example: example) },
      sourceValidation: { try ExampleAcceptance.validateSource($0, example: example) },
      declarationValidation: { try ExampleAcceptance.validate($0, example: example) },
      semanticValidation: { try ExampleAcceptance.validate($0, example: example) },
      finalValidation: { document in
        switch example {
        case .meal: try ExampleInteractionAcceptance.validateMeal(document, registry: registry)
        case .bill: try BillInteractionAcceptance.validate(document, registry: registry)
        case .equipment: try EquipmentInteractionAcceptance.validate(document, registry: registry)
        }
      })
  }
}

/// The product path is chat → provider → strict JSON → generic native document.
private struct ChatScreen: View {
  private let calculations: CalculationRegistry?
  @State private var documentState = DocumentState()
  @State private var session: DocumentChatSession
  @State private var modeLabel: String
  @State private var input = ""
  @State private var selectedExample: InteractiveExample?
  @State private var panel = "Chat"
  @State private var syntheticPreviewAdvanced = false
  @State private var selectedPreviewForRequest = false
  @State private var sourceShown = false
  @State private var jsonShown = false
  @State private var originalShown = false
  @State private var comparison = "Chat"
  @State private var originalSources: [String] = []
  @State private var hostResult = ""
  @FocusState private var composerFocused: Bool

  init() {
    let args = ProcessInfo.processInfo.arguments
    let provider: any DocumentGenerationProvider
    let label: String
    let calculations = args.contains("--interactive-examples") ? try! ExampleCalculations.registry() : nil
    self.calculations = calculations
    #if DEBUG && targetEnvironment(simulator)
    let fixtureArgument = args.firstIndex(of: "--chat-document-file")
    if let index = fixtureArgument {
      let path = args.indices.contains(index + 1) ? args[index + 1] : nil
      provider = ChatDocumentFileProvider(path: path)
      label = "Synthetic fixture · not AI generation"
    } else {
      (provider, label) = Self.defaultProvider(arguments: args)
    }
    #else
    (provider, label) = Self.defaultProvider(arguments: args)
    #endif
    _session = State(
      initialValue: DocumentChatSession(provider: provider, registeredActions: ["acknowledge"], calculations: calculations))
    _modeLabel = State(initialValue: label)
  }

  private static func defaultProvider(arguments args: [String]) -> (any DocumentGenerationProvider, String) {
    let provider: any DocumentGenerationProvider
    let label: String
    if args.contains("--chat-progressive-fixture") {
      provider = ChatProgressiveFixtureProvider.shared
      label = "Synthetic progressive provider · not AI generation"
    } else if let index = args.firstIndex(of: "--chat-reference"), args.indices.contains(index + 1) {
      provider = ReferenceReadingProvider(scenario: args[index + 1])
      label = "Synthetic reference fixture · not AI generation"
    } else if args.contains("--chat-rich-output") {
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
    return (provider, label)
  }

  var body: some View {
    GeometryReader { geometry in
      let wide = geometry.size.width >= 900
      VStack(spacing: 8) {
        header
        if calculations != nil {
          HStack {
            ForEach(InteractiveExample.allCases, id: \.self) { example in
              Button(example.rawValue) {
                selectedExample = example
                input = example.prompt
              }
              .frame(minHeight: 44)
              .accessibilityValue(selectedExample == example ? "Selected" : "")
            }
          }.font(.caption).disabled(session.phase == .generating)
          Text(selectedExample.map { "Selected example acceptance: \($0.rawValue)" }
            ?? "Choose an example to apply its acceptance checks.")
            .font(.caption).foregroundStyle(.secondary)
            .accessibilityIdentifier("example-acceptance")
          Text("Synthetic source data · provider shown in Details")
            .font(.caption).foregroundStyle(.secondary)
        }
        if !wide {
          Group {
            HStack(spacing: 0) {
              ForEach(["Chat", "Document"], id: \.self) { value in
                Button {
                  panel = value
                } label: {
                  Text(value).font(.subheadline.weight(panel == value ? .semibold : .regular))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background {
                      if panel == value { Capsule().fill(.background.secondary) }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityValue(panel == value ? "Selected" : "")
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
        if ProcessInfo.processInfo.arguments.contains("--chat-progressive-fixture") {
          Button("Advance synthetic preview") {
            Task {
              await ChatProgressiveFixtureProvider.shared.advance()
              syntheticPreviewAdvanced = true
            }
          }
          if syntheticPreviewAdvanced { Text("Synthetic preview attempt advanced") }
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
              VStack(spacing: 12) {
                if wide && !originalSources.isEmpty {
                  HStack {
                    Button("Chat") { comparison = "Chat" }.accessibilityIdentifier("comparison-chat")
                    Spacer()
                    Button("Original text") { comparison = "Original" }.accessibilityIdentifier("original-source")
                  }.padding(.horizontal, 16)
                }
                if wide && comparison == "Original" {
                  ScrollView { originalSourceCard.padding(20) }
                } else { conversation }
              }.frame(maxWidth: wide ? geometry.size.width * 0.34 : .infinity)
            }
            if wide || panel == "Document" { documentPanel(wide: wide) }
          }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
        composer.padding(.top, 4).padding(.bottom, 8)
      }
      .padding(.horizontal, wide ? 28 : 16).padding(.top, 12)
      
    }
    .onChange(of: session.revision) { _, _ in hostResult = "" }
    .onChange(of: session.phase) { _, phase in
      if phase == .generating { selectedPreviewForRequest = false }
    }
    .onChange(of: session.previewSequence) { _, sequence in
      if !selectedPreviewForRequest && sequence != nil {
        selectedPreviewForRequest = true
        panel = "Document"
      }
    }
    .sheet(isPresented: $originalShown) {
      NavigationStack {
        ScrollView { GlassEffectContainer { originalSourceCard.padding(20) } }
          .navigationTitle("Original text").navigationBarTitleDisplayMode(.inline)
          .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { originalShown = false } } }
      }
    }
    .sheet(isPresented: $sourceShown) {
      NavigationStack {
        ScrollView {
          VStack(alignment: .leading, spacing: 20) {
            Text("Model source").font(.headline)
            Text(modeLabel).font(.callout).textSelection(.enabled)
              .accessibilityIdentifier("chat-provider-label")
            Text(session.revision == 0 ? "DOCUMENT" : "DOCUMENT · \(session.revision)")
              .font(.caption.bold()).accessibilityIdentifier("chat-revision")
            Button("View JSON") { jsonShown = true }
              .disabled(session.document == nil).accessibilityIdentifier("chat-show-json")
            if jsonShown {
              Text(String(decoding: session.documentJSON ?? Data(), as: UTF8.self))
                .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("chat-json-source")
            }
          }.frame(maxWidth: .infinity, alignment: .leading).padding(20)
        }
        .navigationTitle("Details").navigationBarTitleDisplayMode(.inline)
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
          Text("SwiftUIIntelligence").font(.headline)

        }
        Spacer(minLength: 8)
        Button { jsonShown = false; sourceShown = true } label: {
          Image(systemName: "info.circle").frame(width: 44, height: 44)
        }
          .accessibilityLabel("Details").accessibilityIdentifier("chat-details")
        Button {
          session.reset()
          selectedExample = nil
          documentState = DocumentState()
          originalSources = []
          comparison = "Chat"
          originalShown = false
          hostResult = ""
          panel = "Chat"
        } label: {
          Image(systemName: "square.and.pencil").frame(width: 44, height: 44)
        }
        .accessibilityLabel("New chat").accessibilityIdentifier("chat-reset")
      }
      if modeLabel.contains("Unavailable") {
        Button("Try synthetic demo") {
          session = DocumentChatSession(
            provider: SyntheticChatProvider(), registeredActions: ["acknowledge"], calculations: calculations)
          modeLabel = "Synthetic provider · not AI generation"
        }.accessibilityIdentifier("chat-use-synthetic")
      }
    }
    .padding(.horizontal, 4)
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

  private var originalSourceCard: some View {
    VStack(alignment: .leading, spacing: 16) {
      Label("Original text", systemImage: "doc.text").font(.headline)
      ForEach(Array(originalSources.enumerated()), id: \.offset) { index, source in
        VStack(alignment: .leading, spacing: 8) {
          if originalSources.count > 1 {
            Text("Message \(index + 1)").font(.caption).foregroundStyle(.secondary)
          }
          Text(source).font(.body).textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("source-text-\(index)")
        }
      }
    }
    .modifier(SwiftUIIntelligenceSurface(inset: 16))
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("original-source-card")
  }

  private func documentPanel(wide: Bool) -> some View {
    VStack(spacing: 12) {
      if !wide && !originalSources.isEmpty {
        HStack {
          Spacer()
          Button { originalShown = true } label: {
            Label("Original text", systemImage: "doc.text").font(.subheadline).frame(minHeight: 44)
          }.accessibilityIdentifier("original-source")
        }.padding(.horizontal, 20)
      }
      ScrollView {
        GlassEffectContainer {
        VStack(alignment: .leading, spacing: 20) {
        if session.phase == .generating {
          ForEach(Array(session.previewComponents.enumerated()), id: \.offset) { _, component in
            DocumentPreviewView(document: component, calculations: session.calculationRegistry, embedded: true)
              .id("\(session.previewAttemptID?.uuidString ?? ""):\(component.root.id)")
          }
        }
        if let document = session.document {
          SwiftUIIntelligenceView(
            document: document,
            actions: ActionRegistry([
              "acknowledge": {
                hostResult = "Host acknowledged the document."
                return hostResult
              }
            ]), embedded: true, state: documentState, calculations: calculations
          )
          .id(session.revision).frame(maxWidth: .infinity, alignment: .leading)
        } else {
          ContentUnavailableView(
            "Your document appears here", systemImage: "doc.text",
            description: Text("Only validated, complete JSON is rendered.")
          )

        }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 24)
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
        let validation = calculations.flatMap { registry in selectedExample?.policy(registry: registry) }
        originalSources.append(message)
        input = ""
        composerFocused = false
        Task {
          await session.send(message, validation: validation)
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

#if DEBUG && targetEnvironment(simulator)
/// Simulator-only fixture input. The session owns document and example validation.
private actor ChatDocumentFileProvider: DocumentGenerationProvider {
  private let path: String?
  private static let maximumBytes = 65_536

  init(path: String?) { self.path = path }

  func generate(_ request: DocumentGenerationRequest) async throws -> Data {
    try Task.checkCancellation()
    guard let path, !path.isEmpty, !path.hasPrefix("--"),
      !path.contains(":"), !path.contains("\0"),
      !path.split(separator: "/").contains("..")
    else { throw UIError("Synthetic fixture path is invalid.") }

    let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
      .standardizedFileURL.resolvingSymlinksInPath()
    let candidate = path.hasPrefix("/")
      ? URL(fileURLWithPath: path).standardizedFileURL
      : home.appendingPathComponent(path).standardizedFileURL
    let resolved = candidate.resolvingSymlinksInPath()
    let homeComponents = home.pathComponents
    guard resolved.pathComponents.count > homeComponents.count,
      resolved.pathComponents.starts(with: homeComponents)
    else { throw UIError("Synthetic fixture path is invalid.") }

    do {
      // Inspect the supplied path, not only its resolved destination. No symlink is allowed.
      var componentURL = URL(fileURLWithPath: "/", isDirectory: true)
      for component in candidate.pathComponents.dropFirst() {
        componentURL.appendPathComponent(component)
        let attributes = try FileManager.default.attributesOfItem(atPath: componentURL.path)
        guard attributes[.type] as? FileAttributeType != .typeSymbolicLink else {
          throw UIError("Synthetic fixture path is invalid.")
        }
      }
      let attributes = try FileManager.default.attributesOfItem(atPath: resolved.path)
      guard attributes[.type] as? FileAttributeType == .typeRegular else {
        throw UIError("Synthetic fixture could not be read.")
      }
      let handle = try FileHandle(forReadingFrom: resolved)
      defer { try? handle.close() }
      var bytes = Data()
      while bytes.count <= Self.maximumBytes {
        try Task.checkCancellation()
        let chunk = try handle.read(upToCount: Self.maximumBytes + 1 - bytes.count) ?? Data()
        if chunk.isEmpty { break }
        bytes.append(chunk)
      }
      guard bytes.count <= Self.maximumBytes else {
        throw UIError("Synthetic fixture exceeds 65536 bytes.")
      }
      try Task.checkCancellation()
      return bytes
    } catch is CancellationError {
      throw CancellationError()
    } catch let error as UIError {
      throw error
    } catch {
      throw UIError("Synthetic fixture could not be read.")
    }
  }
}
#endif

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
    if failure == "meal-source" || failure == "meal-projection" {
      return try Self.mealFixture(changedSource: count > 1 && failure == "meal-source", missingProjection: count > 1 && failure == "meal-projection")
    }
    let number = ["provider", "malformed", "unknown"].contains(failure) ? count - 1 : count
    return Data((number == 1 ? Self.plan : Self.handover).utf8)
  }
  /// Deterministic acceptance regression data, never selected from user text.
  private static func mealFixture(changedSource: Bool, missingProjection: Bool) throws -> Data {
    func collection(_ id: String, fields: [String: String], rows: [[String: Any]]) -> [String: Any] {
      ["id": id, "schema": ["fields": fields], "rows": rows.enumerated().map {
        ["id": "row-\($0.offset)", "values": $0.element]
      }]
    }
    let children: [[String: Any]] = [
      ["id": "fixture-title", "type": "text", "text": "Synthetic meal acceptance fixture"],
      ["id": "fixture-people", "type": "control", "title": "People", "controlType": "stepper", "binding": "people"],
      ["id": "fixture-time", "type": "control", "title": "Meal time", "controlType": "datePicker", "binding": "time"],
      ["id": "fixture-shopping", "type": "table", "columns": ["Ingredient", "Quantity", "Unit"], "rows": [["Pending", "Pending", "Pending"]], "recordSource": "shopping", "recordFields": ["name", "quantity", "unit"]],
      ["id": "fixture-schedule", "type": "timeline", "title": "Schedule", "events": [["time": "Start", "title": "Step", "detail": "End"]], "recordSource": "schedule", "recordFields": ["start", "title", "end"]],
    ]
    let source: [String: Any] = [
      "version": 1,
      "state": [
        ["id": "base", "kind": "number", "value": 2, "minimum": 1, "maximum": MealPlanning.maximumPeople, "step": 1],
        ["id": "people", "kind": "number", "value": 3, "minimum": 1, "maximum": MealPlanning.maximumPeople, "step": 1],
        ["id": "time", "kind": "date", "value": "2026-10-15T19:00:00Z"],
      ],
      "records": [
        collection("ingredients", fields: ["name": "text", "quantity": "number", "unit": "text"], rows:
          zip(["lentils", "rice", "carrots"], [changedSource ? 201 : 200, 150, 100]).map {
            ["name": $0.0, "quantity": $0.1, "unit": "g"]
          }),
        collection("steps", fields: ["title": "text", "minutes": "number"], rows:
          zip(["preparation", "cooking", "serving"], [10, 25, 5]).map { ["title": $0.0, "minutes": $0.1] }),
      ],
      "calculations": [["id": "fixture-plan", "capability": "meal-plan",
        "inputs": ["basePeople": "base", "people": "people", "mealTime": "time"],
        "outputs": [String: String](), "recordInputs": ["ingredients": "ingredients", "steps": "steps"],
        "recordOutputs": ["shopping": "shopping", "schedule": "schedule"]]],
      "root": ["id": "fixture-root", "type": "vstack", "children": missingProjection ? Array(children.dropLast()) : children],
    ]
    return try JSONSerialization.data(withJSONObject: source, options: [.sortedKeys])
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

/// Synthetic reference scenes verify reading structure without claiming model inference.
private struct ReferenceReadingProvider: DocumentGenerationProvider {
  let scenario: String
  func generate(_ request: DocumentGenerationRequest) async throws -> Data {
    let json = scenario == "events" ? Self.events : Self.narrative
    return Data(json.utf8)
  }

  private static let narrative = #"{"version":1,"root":{"id":"reference-root","type":"vstack","spacing":20,"children":[{"id":"reference-overview","type":"section","title":"Cyanotype","spacing":16,"children":[{"id":"reference-answer","type":"text","style":"body","text":"The cyanotype process was invented in 1842 by English astronomer and chemist Sir John Herschel. He developed the method to copy his scientific notes, using light-sensitive iron salts to create a distinctive Prussian blue print."}]},{"id":"reference-process","type":"section","title":"How the print forms","spacing":12,"children":[{"id":"reference-steps","type":"iconList","iconItems":[{"text":"Light-sensitive iron salts provide the coating.","icon":"info"},{"text":"Light exposes the coated surface.","icon":"sun"},{"text":"The process produces a Prussian blue print.","icon":"checklist"}]}]}]},"floatingActions":[]}"#
  private static let events = #"{"version":1,"root":{"id":"reference-events-root","type":"vstack","spacing":20,"children":[{"id":"reference-intro","type":"text","style":"body","text":"Here are the upcoming birthday celebrations in this supplied example. These are synthetic events, not events from your calendar."},{"id":"reference-events","type":"timeline","title":"Birthday celebrations","events":[{"time":"Wednesday, April 1","title":"Maiko’s birthday","detail":"All-day","cardColor":"orange"},{"time":"Friday, April 17","title":"Birthday celebration for Nick, Juan, and Vicki","detail":"Apr 17, 3:00–4:00 PM","cardColor":"blue"},{"time":"Tuesday, April 28","title":"Hunter’s birthday","detail":"All-day","cardColor":"orange"}]}]},"floatingActions":[]}"#
}
