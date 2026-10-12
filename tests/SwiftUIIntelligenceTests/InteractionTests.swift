import Foundation
import Testing
import SwiftUIIntelligence
import SwiftUIIntelligenceFoundationModels

private let interactiveJSON = #"{"version":1,"state":[{"id":"enabled","kind":"boolean","value":false},{"id":"name","kind":"text","value":"Guest"},{"id":"seats","kind":"number","value":2,"minimum":1,"maximum":8,"step":1}],"root":{"id":"root","type":"vstack","children":[{"id":"form","type":"form","title":"Settings","children":[{"id":"toggle","type":"control","title":"Enabled","binding":"enabled","controlType":"toggle"},{"id":"name-input","type":"control","title":"Name","binding":"name","controlType":"textField"},{"id":"count","type":"control","title":"Seats","binding":"seats","controlType":"stepper"}]},{"id":"link","type":"navigationLink","title":"Details","destination":"detail"},{"id":"detail","type":"section","title":"Notes","children":[{"id":"events","type":"timeline","title":"Schedule","events":[{"time":"09:00","title":"Setup","detail":"Prepare"}]}]}]}}"#

@Test @MainActor func typedEditsValidateAndSurviveReload() throws {
  let document = try UIDocument.decode(Data(interactiveJSON.utf8), registeredActions: [])
  let state = DocumentState(); state.load(document)
  try state.set("enabled", to: .boolean(true))
  try state.set("name", to: .text("Edited"))
  #expect(throws: UIError.self) { try state.set("seats", to: .number(9)) }
  #expect(throws: UIError.self) { try state.set("enabled", to: .text("true")) }
  #expect(throws: UIError.self) { try state.set("unknown", to: .boolean(true)) }
  state.load(document)
  #expect(state.values["name"] == .text("Edited"))
  #expect(state.values["enabled"] == .boolean(true))
  state.load(document, preservingEdits: false)
  #expect(state.values["enabled"] == .boolean(false))
  let again = try UIDocument.decode(DocumentGenerationContract.canonicalJSON(document), registeredActions: [])
  #expect(again.state.count == 3)
}

@Test(arguments: [
  ("\"binding\":\"enabled\"", "\"binding\":\"missing\""),
  ("\"controlType\":\"toggle\"", "\"controlType\":\"slider\""),
  ("\"destination\":\"detail\"", "\"destination\":\"missing\""),
  ("\"kind\":\"boolean\",\"value\":false", "\"kind\":\"boolean\",\"value\":\"false\""),
  ("\"maximum\":8", "\"maximum\":0"),
  ("\"kind\":\"text\"", "\"kind\":\"date\""),
  ("\"id\":\"name\",\"kind\"", "\"id\":\"enabled\",\"kind\""),
  ("\"time\":\"09:00\"", "\"time\":\"\""),
]) func badBindingsReferencesAndTypesAreRejected(change: (String, String)) {
  let json = interactiveJSON.replacingOccurrences(of: change.0, with: change.1)
  #expect(throws: UIError.self) { try UIDocument.decode(Data(json.utf8), registeredActions: []) }
}

@Test @MainActor func asyncCapabilityReceivesTypedStateAndIdentity() async throws {
  var eventIDs = Set<UUID>()
  let actions = ActionRegistry(async: ["submit": { event in
    #expect(event.state["enabled"] == .boolean(true))
    eventIDs.insert(event.id)
    return "Received"
  }])
  #expect(actions.names == ["submit"])
  let event = ActionEvent(action: "submit", state: ["enabled": .boolean(true)])
  #expect(try await actions.perform(event) == "Received")
  #expect(eventIDs == [event.id])
  await #expect(throws: UIError.self) { try await actions.perform(ActionEvent(action: "delete", state: [:])) }
}

private actor InteractiveProvider: DocumentGenerationProvider {
  var count = 0
  func generate(_ request: DocumentGenerationRequest) async throws -> Data {
    count += 1
    if count == 2 { return Data(interactiveJSON.replacingOccurrences(of: "Settings", with: "Changed").utf8) }
    return Data(interactiveJSON.utf8)
  }
}
@Test @MainActor func sharedSessionSemanticFailureKeepsPriorDocument() async {
  let session = DocumentChatSession(provider: InteractiveProvider(), requirements: .init(components: [.form, .control, .timeline, .navigationLink], exactText: ["Settings"]))
  await session.send("Settings")
  #expect(session.phase == .ready)
  await session.send("Revise")
  #expect(session.phase == .failed && session.failureKind == .invalidDocument)
  #expect(session.revision == 1 && session.document != nil && session.canRetry)
}

private actor IgnoringCancellationProvider: DocumentGenerationProvider {
  func generate(_ request: DocumentGenerationRequest) async throws -> Data {
    try? await Task.sleep(for: .milliseconds(150))
    return Data(interactiveJSON.utf8)
  }
}
@Test @MainActor func publicCancelInvalidatesLateCompletionAndAllowsNextRequest() async throws {
  let session = DocumentChatSession(provider: IgnoringCancellationProvider())
  let task = Task { await session.send("First") }
  try await Task.sleep(for: .milliseconds(20))
  session.cancel()
  await task.value
  #expect(session.phase == .idle && session.document == nil && session.revision == 0)
  await session.send("Second")
  #expect(session.phase == .ready && session.revision == 1)
}

private struct SnapshotProvider: StreamingDocumentGenerationProvider {
  func generate(_ request: DocumentGenerationRequest) async throws -> Data { Data(interactiveJSON.utf8) }
  func generate(_ request: DocumentGenerationRequest, onSnapshot: @escaping @Sendable (Data) -> Void) async throws -> Data {
    onSnapshot(Data("{".utf8)); try await Task.sleep(for: .milliseconds(20))
    onSnapshot(Data(interactiveJSON.utf8)); try await Task.sleep(for: .milliseconds(20))
    return Data(interactiveJSON.utf8)
  }
}
@Test @MainActor func cumulativeSnapshotsNeverCommitPartialDocuments() async throws {
  let session = DocumentChatSession(provider: SnapshotProvider())
  let task = Task { await session.send("Generate") }
  try await Task.sleep(for: .milliseconds(10))
  #expect(session.phase == .generating && session.document == nil && session.revision == 0)
  await task.value
  #expect(session.phase == .ready && session.revision == 1 && session.snapshotCount == 2)
}

@Test func schemaMatchesPublicComponentCatalog() throws {
  let object = try JSONSerialization.jsonObject(with: DocumentGenerationContract.schemaJSON(registeredActions: ["submit"])) as! [String: Any]
  let definitions = object["$defs"] as! [String: Any]
  #expect(Set(definitions.keys).subtracting(["Icon", "Node"]) == Set(ComponentCatalog.components.map(\.rawValue)))
}

@Test @MainActor func timeoutRejectsLateCompletionAndRetainsRetry() async throws {
  let session = DocumentChatSession(provider: IgnoringCancellationProvider(), timeout: .milliseconds(10))
  await session.send("Too slow")
  #expect(session.phase == .failed && session.canRetry && session.document == nil)
  #expect(session.errorMessage?.contains("timed out") == true)
}

@Test @MainActor func revisionsApplyUntouchedDefaultsAndRetainOnlyUserEdits() throws {
  let original = try UIDocument.decode(Data(interactiveJSON.utf8), registeredActions: [])
  let revised = try UIDocument.decode(Data(interactiveJSON.replacingOccurrences(of: "Guest", with: "New default").utf8), registeredActions: [])
  let state = DocumentState(); state.load(original)
  try state.set("enabled", to: .boolean(true))
  state.load(revised)
  #expect(state.values["name"] == .text("New default"))
  #expect(state.values["enabled"] == .boolean(true))
}

@Test func readOnlyNativeGroupsDoNotCarryUnusedInteractiveStateSchema() throws {
  let request = try DocumentGenerationRequest(messages: [.init(role: .user, content: "Synthetic metrics")])
  let schema = try FoundationModelsDocumentProvider.generationSchema(for: request, componentTypes: ["metric"])
  let encoded = String(decoding: try JSONEncoder().encode(schema), as: UTF8.self)
  #expect(!encoded.contains("\"state\""))
}
