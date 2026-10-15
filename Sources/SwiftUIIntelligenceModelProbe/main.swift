import Foundation
import SwiftUIIntelligence
import SwiftUIIntelligenceFoundationModels

@main struct ModelProbe {
  @MainActor static func main() async {
    let args = CommandLine.arguments
    let folder = URL(
      fileURLWithPath: args.dropFirst().first ?? "/tmp/swiftuiintelligence-model-output", isDirectory: true)
    do {
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      let availability = FoundationModelsDocumentProvider.availabilityDescription
      print(availability)
      try Data(availability.utf8).write(to: folder.appendingPathComponent("availability.txt"))
      if args.contains("--scenarios") { try await scenarioProbe(folder, filter: args.last == "--scenarios" ? nil : args.last); return }
      if let flag = args.firstIndex(of: "--prompt-file"), args.indices.contains(flag + 1) {
        try await promptProbe(folder, promptURL: URL(fileURLWithPath: args[flag + 1]))
        return
      }
      if args.contains("--rich") {
        try await richProbe(folder)
        return
      }
      if let flag = args.firstIndex(of: "--openai-compatible"), args.indices.contains(flag + 2) {
        try await openAIProbe(folder, endpoint: args[flag + 1], model: args[flag + 2])
        return
      }
      let prompts = Self.handoverPrompts
      var messages: [ChatMessage] = []
      var semanticFailures: [String] = []
      for (index, prompt) in prompts.enumerated() {
        messages.append(ChatMessage(role: .user, content: prompt))
        if args.contains("--resume-third") && index < 2 {
          let saved = try Data(
            contentsOf: folder.appendingPathComponent("document-\(index + 1).json"))
          let document = try UIDocument.decode(saved, registeredActions: [])
          try verifySemantics(document, turn: index + 1)
          messages.append(
            ChatMessage(role: .assistant, content: String(decoding: saved, as: UTF8.self)))
          print("Retained real response \(index + 1): revalidated")
          continue
        }
        let request = try DocumentGenerationRequest(messages: messages)
        try request.schemaJSON.write(to: folder.appendingPathComponent("schema.json"))
        try request.conversationJSON().write(
          to: folder.appendingPathComponent("request-\(index + 1).json"))
        let draftURL = folder.appendingPathComponent("draft-\(index + 1).json")
        let provider = FoundationModelsDocumentProvider(onDraft: { data in
          try? data.write(to: draftURL)
        })
        let raw = try await provider.generate(request)
        try raw.write(to: folder.appendingPathComponent("raw-\(index + 1).json"))
        let valid = try UIDocument.decode(raw, registeredActions: [])
        let json = try DocumentGenerationContract.canonicalJSON(valid)
        do { try verifySemantics(valid, turn: index + 1) } catch {
          semanticFailures.append(error.localizedDescription)
          print(error.localizedDescription)
        }
        try json.write(to: folder.appendingPathComponent("document-\(index + 1).json"))
        messages.append(
          ChatMessage(role: .assistant, content: String(decoding: json, as: UTF8.self)))
        print("Real on-device response \(index + 1): validated \(json.count) bytes")
      }
      if semanticFailures.isEmpty {
        try Data(
          "passed: 3 real on-device generations with structure and authored semantic assertions, including follow-up and different domain\n"
            .utf8
        ).write(to: folder.appendingPathComponent("status.txt"))
      } else {
        try Data(
          ("semantic failures after 3 structurally valid real responses:\n"
            + semanticFailures.joined(separator: "\n")).utf8
        ).write(to: folder.appendingPathComponent("status.txt"))
        exit(2)
      }
    } catch {
      try? Data(String(reflecting: error).utf8).write(to: folder.appendingPathComponent("error-debug.txt"))
      let message = "failed: \(error.localizedDescription)\n"
      print(message)
      try? Data(message.utf8).write(to: folder.appendingPathComponent("status.txt"))
      exit(1)
    }
  }
  static func promptProbe(_ folder: URL, promptURL: URL) async throws {
    let prompt = try String(contentsOf: promptURL, encoding: .utf8)
    let request = try DocumentGenerationRequest(messages: [.init(role: .user, content: prompt)])
    try request.conversationJSON().write(to: folder.appendingPathComponent("request.json"))
    try request.schemaJSON.write(to: folder.appendingPathComponent("schema.json"))
    try Data(request.instructions.utf8).write(to: folder.appendingPathComponent("instructions.txt"))
    let provider = FoundationModelsDocumentProvider(onDraft: { data in
      try? data.write(to: folder.appendingPathComponent("draft.json"))
    }, onTrace: { name, data in
      let suffix = name.hasSuffix("error") || name.hasSuffix("accepted") || name.hasSuffix("debug") ? "txt" : "json"
      try? data.write(to: folder.appendingPathComponent("trace-" + name + "." + suffix))
    })
    let start = Date()
    let raw = try await provider.generate(request)
    try raw.write(to: folder.appendingPathComponent("raw.json"))
    let document = try UIDocument.decode(raw, registeredActions: [])
    try DocumentGenerationContract.canonicalJSON(document).write(to: folder.appendingPathComponent("document.json"))
    let result = "passed: real Apple on-device grouped generation; strict structure validated; seconds=\(Date().timeIntervalSince(start))\n"
    try Data(result.utf8).write(to: folder.appendingPathComponent("status.txt"))
    print(result)
  }

  static func richProbe(_ folder: URL) async throws {
    let prompt = """
    Create a compact dashboard for an invented community workshop. Use ONLY these supplied facts. Title: Workshop readiness. Metric: Volunteers = 12 people, detail Registered, people icon. Status badge: Ready. Progress: Safety checks, completed 3, total 5. Icon list: Prepare the tool bench (task icon); Review the guide (book icon). Line chart: Attendance, series Visitors, Mon=8, Tue=12, Wed=10. Use metric, badge, progress, iconList and chart nodes with semantic catalog icons. Put the title first and the rich components below it. Do not duplicate all facts in a paragraph. Keep all numeric values exactly as given. Use unique simple IDs. Do not add weather, names, dates, targets or extra chart points. This request is synthetic.
    """
    let request = try DocumentGenerationRequest(messages: [.init(role: .user, content: prompt)])
    try request.schemaJSON.write(to: folder.appendingPathComponent("schema.json"))
    try request.conversationJSON().write(to: folder.appendingPathComponent("request.json"))
    let provider = FoundationModelsDocumentProvider(onDraft: { data in
      try? data.write(to: folder.appendingPathComponent("draft.json"))
    })
    let start = Date()
    let raw = try await provider.generate(request)
    try raw.write(to: folder.appendingPathComponent("raw.json"))
    let document = try UIDocument.decode(raw, registeredActions: [])
    let canonical = try DocumentGenerationContract.canonicalJSON(document)
    try canonical.write(to: folder.appendingPathComponent("document.json"))
    var nodes: [UINode] = []
    func walk(_ node: UINode) { nodes.append(node); node.children.forEach(walk) }
    walk(document.root)
    let kinds = Set(nodes.map(\.type))
    guard [.metric, .badge, .progress, .iconList, .chart].allSatisfy(kinds.contains),
      nodes.contains(where: { $0.type == .metric && $0.value.contains("12") }),
      nodes.contains(where: { $0.type == .progress && $0.completed == 3 && $0.total == 5 }),
      nodes.contains(where: { $0.type == .iconList && $0.iconItems.count == 2 }),
      nodes.contains(where: { $0.type == .chart && $0.chartStyle == .line && $0.points.map(\.value) == [8, 12, 10] }),
      nodes.allSatisfy({ $0.icon.map(SymbolCatalog.isKnown) ?? true }),
      nodes.flatMap(\.iconItems).allSatisfy({ SymbolCatalog.isKnown($0.icon) })
    else { throw UIError("Rich model output failed authored semantic/component assertions.") }
    let result = "passed: real Apple on-device generation, 5 rich component kinds, catalog icons and exact synthetic numeric assertions; seconds=\(Date().timeIntervalSince(start))\n"
    try Data(result.utf8).write(to: folder.appendingPathComponent("status.txt"))
    print(result)
  }

  static func verifySemantics(_ document: UIDocument, turn: Int) throws {
    var nodes: [UINode] = []
    func collect(_ node: UINode) {
      nodes.append(node)
      node.children.forEach(collect)
    }
    collect(document.root)
    let text = nodes.flatMap { [$0.text, $0.title] + $0.items + $0.rows.flatMap { $0 } }.joined(
      separator: " "
    ).lowercased()
    if turn <= 2 {
      let table = nodes.first { $0.type == .table }
      let time = turn == 1 ? "2pm" : "3pm"
      let rows = table?.rows.map { $0.joined(separator: " ").lowercased() } ?? []
      guard table?.columns.count == 2, rows.count == 2,
        rows.contains(where: { $0.contains("welcome") && $0.contains("10am") }),
        rows.contains(where: { $0.contains("sorting") && $0.contains(time) }),
        turn == 1 || (!text.contains("2pm") && text.contains("10 minutes"))
      else {
        throw UIError(
          "Semantic assertion failed on turn \(turn): supplied shifts or follow-up were not applied consistently."
        )
      }
    } else {
      guard text.contains("export"), text.contains("pending"), !text.contains("welcome desk"),
        !text.contains("book sorting"), !text.contains("14:00"), !text.contains("tomorrow"),
        !text.contains("meeting"),
        nodes.contains(where: { $0.type == .list }), nodes.contains(where: { $0.type == .callout })
      else { throw UIError("Semantic assertion failed: release handover/domain switch.") }
    }
  }

  static let handoverPrompts: [String] = [
    "Create a short neighborhood library volunteer plan. Include a title, one preparation section with a three-item list, and a table with exactly two columns Task and Time, exactly two rows: Welcome desk | 10am; Book sorting | 2pm. These are invented Saturday shifts. Copy these values exactly. Do not add other shifts or names.",
    "Revise the existing volunteer plan. In the table change Book sorting from 2pm to 3pm, retaining Welcome desk at 10am. Also add a new callout node with the exact text: Volunteers should arrive 10 minutes early. Preserve the other preparation items.",
    "Create a NEW document about a different topic: an invented offline notes app handover. Use ONLY this content: checklist items Check offline save and Check restore; warning note Export testing is pending. Put the checklist in a section with a list and the warning in a callout. Do not add meetings, schedules, versions, names, dates or deadlines. Do not carry over any library content.",
  ]

  /// Acceptance run against a remote OpenAI-compatible endpoint through URLSession.
  static func openAIProbe(_ folder: URL, endpoint: String, model: String) async throws {
    guard let url = URL(string: endpoint) else { throw UIError("Invalid endpoint URL.") }
    guard let key = ProcessInfo.processInfo.environment["SWIFTUIINTELLIGENCE_API_KEY"],
      !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { throw UIError("Set SWIFTUIINTELLIGENCE_API_KEY to the endpoint API key.") }
    let provider = try OpenAICompatibleDocumentProvider(endpoint: url, apiKey: key, model: model)
    let transport = "provider=OpenAICompatibleDocumentProvider scheme=\(url.scheme ?? "unknown") host=\(url.host ?? "unknown") model=\(model)" + "\n"
    try Data(transport.utf8).write(to: folder.appendingPathComponent("transport.txt"))
    var messages: [ChatMessage] = []
    var semanticFailures: [String] = []
    for (index, prompt) in handoverPrompts.enumerated() {
      messages.append(ChatMessage(role: .user, content: prompt))
      let request = try DocumentGenerationRequest(messages: messages)
      try request.schemaJSON.write(to: folder.appendingPathComponent("schema.json"))
      try request.conversationJSON().write(to: folder.appendingPathComponent("request-\(index + 1).json"))
      let start = Date()
      let raw = try await provider.generate(request)
      try raw.write(to: folder.appendingPathComponent("raw-\(index + 1).json"))
      let valid = try UIDocument.decode(raw, registeredActions: [])
      let json = try DocumentGenerationContract.canonicalJSON(valid)
      do { try verifySemantics(valid, turn: index + 1) } catch {
        semanticFailures.append(error.localizedDescription)
        print(error.localizedDescription)
      }
      try json.write(to: folder.appendingPathComponent("document-\(index + 1).json"))
      messages.append(ChatMessage(role: .assistant, content: String(decoding: json, as: UTF8.self)))
      let seconds = String(format: "%.2f", Date().timeIntervalSince(start))
      print("Remote response \(index + 1): validated \(json.count) bytes in \(seconds)s")
    }
    let status =
      semanticFailures.isEmpty
      ? "passed: 3 remote provider generations through URLSession, strict structure validation and authored semantic assertions, including follow-up and different domain" + "\n"
      : "semantic failures after 3 structurally valid remote responses:" + "\n" + semanticFailures.joined(separator: "\n") + "\n"
    try Data(status.utf8).write(to: folder.appendingPathComponent("status.txt"))
    if !semanticFailures.isEmpty { exit(2) }
  }
}
