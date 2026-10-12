import Foundation
import SwiftUIIntelligence
import SwiftUIIntelligenceFoundationModels

extension ModelProbe {
  struct Scenario {
    let name: String
    let prompt: String
    let requirements: DocumentRequirements
    let verify: @Sendable (UIDocument) throws -> Void
  }
  static var scenarios: [Scenario] {
    [
      Scenario(name: "study", prompt: "Create a synthetic editable form titled Study session. Include exactly a TextEditor titled Notes default Bring notebook; Slider titled Focus default 60 minimum 0 maximum 100 step 10; DatePicker titled Start default 2026-10-12T09:00:00Z. Use declared typed state and matching controls. No host actions, calendar access or extra fields. Preserve defaults exactly.", requirements: .init(components: [.form, .control], exactText: ["Study session", "Notes", "Bring notebook", "Focus", "Start", "2026-10-12T09:00:00Z"], controls: [.textEditor, .slider, .datePicker], stateCount: 3), verify: { document in
        guard document.state.count == 3, document.state.contains(where: { $0.kind == .number && $0.value == .number(60) && $0.minimum == 0 && $0.maximum == 100 && $0.step == 10 }), document.state.contains(where: { $0.kind == .date && $0.value == .text("2026-10-12T09:00:00Z") }) else { throw UIError("Study form requires exactly three fields with the supplied defaults and ranges.") }
      }),
      Scenario(name: "settings", prompt: "Create an interactive form titled Workshop preferences. Use a TextField labelled Display name, default Guest; Toggle labelled Reminders, default false; Picker labelled Session with options Morning and Afternoon, default Morning; Stepper labelled Seats, default 2, minimum 1 maximum 8 step 1. Declare typed state and matching control bindings. Add a button titled Save preferences using authorized action submit. Synthetic local settings only. No charts or invented facts.", requirements: .init(components: [.form, .control, .button], exactText: ["Workshop preferences", "Display name", "Reminders", "Session", "Seats", "Guest", "Morning", "Afternoon", "Save preferences"], controls: [.textField, .toggle, .picker, .stepper], stateCount: 4), verify: { document in
        let kinds = Set(document.state.map(\.kind))
        guard kinds == [.text, .boolean, .choice, .number], document.state.count == 4,
          document.state.contains(where: { $0.kind == .number && $0.value == .number(2) && $0.minimum == 1 && $0.maximum == 8 }),
          document.state.contains(where: { $0.kind == .boolean && $0.value == .boolean(false) }),
          document.state.contains(where: { $0.kind == .choice && $0.value == .text("Morning") && $0.options == ["Morning", "Afternoon"] }),
          document.state.contains(where: { $0.kind == .text && $0.value == .text("Guest") }),
          nodes(document).filter({ $0.type == .control }).count == 4,
          nodes(document).filter({ $0.type == .button }).count == 1 else { throw UIError("Settings state defaults/count/ranges changed.") }
      }),
      Scenario(name: "navigation", prompt: "Create a compact research hub titled Reading room. Include a navigationLink titled Open research notes that references a section destination by ID. Destination section title must be Research notes; its list has exactly two items: Check offline access; Review source dates. Inside the destination also include a Toggle titled Offline mode bound to one declared boolean state field, default false. Keep destination content in the document so it can be rendered after navigation. No further links, no host actions, no invented facts.", requirements: .init(components: [.navigationLink, .list, .control], exactText: ["Reading room", "Open research notes", "Research notes", "Check offline access", "Review source dates", "Offline mode"], controls: [.toggle], stateCount: 1), verify: { document in
        guard nodes(document).filter({ $0.type == .navigationLink }).count == 1,
          nodes(document).first(where: { $0.type == .list })?.items == ["Check offline access", "Review source dates"], document.state.count == 1, document.state[0].value == .boolean(false) else { throw UIError("Use one list with exactly two items in order: Check offline access; Review source dates.") }
      }),
      Scenario(name: "schedule", prompt: "Create a timeline titled Workshop schedule with exactly three events, preserving each field exactly. Event time 09:00 title Setup detail Prepare tables. Event time 10:00 title Session detail Practice together. Event time 12:00 title Review detail Collect feedback. These are synthetic clock labels, no calendar access or dates. Do not invent events or add prose summaries.", requirements: .init(components: [.timeline], exactText: ["Workshop schedule", "09:00", "Setup", "Prepare tables", "10:00", "Session", "Practice together", "12:00", "Review", "Collect feedback"]), verify: { document in
        let events = nodes(document).filter { $0.type == .timeline }.flatMap(\.events)
        guard events.map(\.time) == ["09:00", "10:00", "12:00"], events.map(\.title) == ["Setup", "Session", "Review"], events.map(\.detail) == ["Prepare tables", "Practice together", "Collect feedback"] else { throw UIError("Timeline event associations changed.") }
      }),
      Scenario(name: "comparison", prompt: "Create a synthetic product comparison titled Desk lamp comparison. Include a table with exactly columns Model, Price, Weight and exactly rows [Aurora, $40, 500 g], [Ember, $55, 620 g]. Add one callout with exact text: Synthetic prices; no purchase action. Do not add products, currency conversion, recommendations or new facts.", requirements: .init(components: [.table, .callout], exactText: ["Desk lamp comparison", "Model", "Price", "Weight", "Aurora", "$40", "500 g", "Ember", "$55", "620 g", "Synthetic prices; no purchase action."]), verify: { document in
        guard let table = nodes(document).first(where: { $0.type == .table }), table.columns == ["Model", "Price", "Weight"], table.rows == [["Aurora", "$40", "500 g"], ["Ember", "$55", "620 g"]] else { throw UIError("Comparison rows changed.") }
      }),
      Scenario(name: "unseen", prompt: "Build a local preferences form titled Reading preferences. Include one Toggle labelled Quiet mode with initial value false. No other inputs, external actions, calendar or analytics. This is synthetic.", requirements: .init(), verify: { document in
        guard nodes(document).contains(where: { $0.type == .form && $0.title == "Reading preferences" }), nodes(document).contains(where: { $0.type == .control && $0.controlType == .toggle && $0.title == "Quiet mode" }), document.state.count == 1, document.state[0].value == .boolean(false) else { throw UIError("Reading preferences must contain exactly the requested Quiet mode toggle with false initial state.") }
      }),
      Scenario(name: "analysis", prompt: "Create a synthetic analytics report titled Studio attendance. Include exactly one bar chart titled Visits with series Visitors and exact points Mon=8, Tue=12, Wed=10 in that order. Include one metric labelled Total, value 30 visits, detail Supplied aggregate, people icon. Aggregate was supplied by host, do not compute other derived numbers. No extra data, no weather.", requirements: .init(components: [.chart, .metric], exactText: ["Studio attendance", "Visits", "Total", "30 visits", "Supplied aggregate"]), verify: { document in
        let charts = nodes(document).filter { $0.type == .chart }
        guard charts.count == 1, charts[0].chartStyle == .bar, charts[0].points.map(\.label) == ["Mon", "Tue", "Wed"], charts[0].points.map(\.value) == [8, 12, 10], charts[0].points.allSatisfy({ $0.series == "Visitors" }) else { throw UIError("Chart supplied data/style changed.") }
      }),
    ]
  }
  static func nodes(_ document: UIDocument) -> [UINode] {
    var result: [UINode] = []
    func visit(_ n: UINode) { result.append(n); n.children.forEach(visit) }
    visit(document.root); document.floatingActions.forEach(visit); return result
  }
  @MainActor static func scenarioProbe(_ folder: URL, filter: String?) async throws {
    var failures = 0
    for scenario in scenarios where filter == nil || scenario.name == filter {
      let destination = folder.appendingPathComponent(scenario.name)
      try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
      try Data(scenario.prompt.utf8).write(to: destination.appendingPathComponent("prompt.txt"))
      let provider = FoundationModelsDocumentProvider(onTrace: { name, data in
        try? data.write(to: destination.appendingPathComponent("trace-" + name + (name.hasSuffix("raw") || name.hasSuffix("schema") ? ".json" : ".txt")))
      })
      let session = DocumentChatSession(provider: provider, registeredActions: scenario.name == "settings" ? ["submit"] : [], requirements: scenario.requirements, semanticValidation: scenario.verify)
      let start = Date()
      await session.send(scenario.prompt)
      let seconds = Date().timeIntervalSince(start)
      var status = "failed: \(session.errorMessage ?? "unknown"); seconds=\(seconds)"
      if let document = session.document, let json = session.documentJSON {
        try scenario.verify(document)
        try json.write(to: destination.appendingPathComponent("document.json"))
        status = "passed: actual Apple model → shared public session → structure + exact authored semantics; seconds=\(seconds); snapshots=\(session.snapshotCount); bytes=\(json.count)"
      } else { failures += 1 }
      try Data(status.utf8).write(to: destination.appendingPathComponent("status.txt"))
      print("\(scenario.name): \(status)")
    }
    if failures > 0 { throw UIError("\(failures) scenarios failed; every attempt retained.") }
  }
}
