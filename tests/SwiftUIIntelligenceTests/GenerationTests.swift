import Foundation
import FoundationModels
import SwiftUIIntelligenceFoundationModels
import Testing

@testable import SwiftUIIntelligence

private let planJSON =
  #"{"version":1,"root":{"id":"plan","type":"vstack","spacing":16,"children":[{"id":"heading","type":"text","text":"Volunteer plan","style":"title"},{"id":"section","type":"section","title":"Preparation","spacing":12,"children":[{"id":"items","type":"list","items":["Open the desk","Sort books"]}]},{"id":"schedule","type":"table","columns":["Task","Time"],"rows":[["Welcome","10am"],["Sort","2pm"]]},{"id":"note","type":"callout","text":"Arrive early","tone":"note"}]},"floatingActions":[]}"#
private let releaseJSON =
  #"{"version":1,"root":{"id":"release","type":"section","title":"Release handover","spacing":12,"children":[{"id":"checks","type":"list","items":["Check offline save","Check export"]},{"id":"pending","type":"callout","text":"Export pending","tone":"warning"}]},"floatingActions":[]}"#

private actor ScriptedProvider: DocumentGenerationProvider {
  enum Outcome: Sendable {
    case json(String)
    case failure
  }
  private var outcomes: [Outcome]
  private(set) var requests: [DocumentGenerationRequest] = []
  init(_ outcomes: [Outcome]) { self.outcomes = outcomes }
  func generate(_ request: DocumentGenerationRequest) async throws -> Data {
    requests.append(request)
    guard !outcomes.isEmpty else { throw UIError("Fixture exhausted") }
    switch outcomes.removeFirst() {
    case .json(let string): return Data(string.utf8)
    case .failure: throw UIError("Synthetic generation error")
    }
  }
}

@Test func genericDocumentNodesRoundTrip() throws {
  let document = try UIDocument.decode(Data(planJSON.utf8), registeredActions: [])
  #expect(document.root.children.map(\.type) == [.text, .section, .table, .callout])
  let data = try DocumentGenerationContract.canonicalJSON(document)
  let roundTrip = try UIDocument.decode(data, registeredActions: [])
  #expect(roundTrip.root.children[2].rows == [["Welcome", "10am"], ["Sort", "2pm"]])
  #expect(roundTrip.root.children[1].children.first?.items.count == 2)
}

@Test(arguments: [
  #"{"id":"r","type":"table","columns":["A","B"],"rows":[["one"]]}"#,
  #"{"id":"r","type":"table","columns":[],"rows":[]}"#,
  #"{"id":"r","type":"list","items":[]}"#,
  #"{"id":"r","type":"list","items":["  "]}"#,
  #"{"id":"r","type":"section","title":"","children":[]}"#,
  #"{"id":"r","type":"callout","text":"Hi","tone":"dangerous"}"#,
  #"{"id":"r","type":"list","items":["Hi"],"html":"<script>"}"#,
]) func invalidDocumentContentIsRejected(node: String) {
  #expect(throws: UIError.self) {
    try UIDocument.decode(Data("{\"version\":1,\"root\":\(node)}".utf8), registeredActions: [])
  }
}

@Test func generationContractAndAppleSchemaAreConstructible() throws {
  let request = try DocumentGenerationRequest(
    messages: [ChatMessage(role: .user, content: "A synthetic plan")],
    registeredActions: ["acknowledge"])
  let schema = try JSONSerialization.jsonObject(with: request.schemaJSON) as! [String: Any]
  let defs = schema["$defs"] as! [String: [String: Any]]
  #expect(defs["button"] != nil)
  #expect((defs["table"]?["anyOf"] as? [[String: Any]])?.count == 6)
  #expect(request.instructions.contains("acknowledge"))
  let appleSchema = try FoundationModelsDocumentProvider.generationSchema(for: request)
  #expect(!(try JSONEncoder().encode(appleSchema)).isEmpty)
  let noActions =
    try JSONSerialization.jsonObject(with: DocumentGenerationContract.schemaJSON())
    as! [String: Any]
  #expect((noActions["$defs"] as! [String: Any])["button"] == nil)
}

@Test @MainActor func multiTurnProviderReceivesValidatedContextAndUpdatesDomain() async throws {
  let provider = ScriptedProvider([.json(planJSON), .json(releaseJSON)])
  let session = DocumentChatSession(provider: provider)
  await session.send("Make a volunteer plan")
  #expect(session.phase == .ready && session.revision == 1)
  await session.send("Change to a release handover")
  #expect(session.phase == .ready && session.revision == 2)
  #expect(session.document?.root.title == "Release handover")
  let calls = await provider.requests
  #expect(calls.count == 2 && calls[1].messages.count == 3)
  #expect(calls[1].messages[1].role == .assistant)
  _ = try UIDocument.decode(Data(calls[1].messages[1].content.utf8), registeredActions: [])
}

@Test @MainActor func rejectedOutputRetainsDocumentAndRetryDoesNotDuplicateTurn() async {
  let unknown = #"{"version":1,"root":{"id":"r","type":"swift","code":"print(1)"}}"#
  let provider = ScriptedProvider([.json(planJSON), .json("{"), .json(unknown), .json(releaseJSON)])
  let session = DocumentChatSession(provider: provider)
  await session.send("Plan")
  let oldData = session.documentJSON
  await session.send("Revise")
  #expect(session.phase == .failed && session.failureKind == .invalidDocument)
  #expect(session.revision == 1 && session.documentJSON == oldData && session.canRetry)
  await session.retry()
  #expect(session.phase == .failed && session.errorMessage?.contains("Unknown component") == true)
  #expect(session.documentJSON == oldData)
  await session.retry()
  #expect(session.phase == .ready && session.revision == 2 && session.messages.count == 4)
  let calls = await provider.requests
  #expect(calls[1].messages == calls[2].messages && calls[2].messages == calls[3].messages)
}

@Test @MainActor func providerFailureAndInputFailureStayRecoverable() async {
  let provider = ScriptedProvider([.failure, .json(planJSON)])
  let session = DocumentChatSession(provider: provider)
  await session.send(" ")
  #expect(session.failureKind == .input && !session.canRetry)
  #expect(await provider.requests.isEmpty)
  await session.send("Synthetic content")
  #expect(session.failureKind == .provider && session.canRetry)
  await session.retry()
  #expect(session.phase == .ready && session.messages.count == 2)
}

@Test @MainActor func resetDiscardsLateProviderCompletion() async {
  let provider = ChatResponseProvider { _ in
    try? await Task.sleep(for: .milliseconds(80))
    return planJSON
  }
  let session = DocumentChatSession(provider: provider)
  let work = Task { await session.send("Plan") }
  await Task.yield()
  session.reset()
  await work.value
  #expect(session.phase == .idle && session.document == nil && session.messages.isEmpty)
}

@Test @MainActor func existingChatAdapterUsesSameValidationBoundary() async {
  let provider = ChatResponseProvider { request in
    request.messages.last?.content == "Valid" ? releaseJSON : "```json\n\(releaseJSON)\n```"
  }
  let session = DocumentChatSession(provider: provider)
  await session.send("Valid")
  #expect(session.phase == .ready)
  await session.send("Wrapped")
  #expect(session.failureKind == .invalidDocument && session.revision == 1)
}

@Test func unsafeBackendAndUnboundedConversationAreRejected() {
  #expect(throws: UIError.self) {
    try HTTPDocumentProvider(endpoint: URL(string: "http://example.com")!)
  }
  #expect(throws: UIError.self) {
    try HTTPDocumentProvider(endpoint: URL(string: "https://key:secret@example.com")!)
  }
  #expect(throws: UIError.self) { try DocumentGenerationRequest(messages: []) }
  #expect(throws: UIError.self) {
    try DocumentGenerationRequest(messages: [
      ChatMessage(role: .user, content: String(repeating: "a", count: 48_001))
    ])
  }
  #expect(throws: UIError.self) {
    try DocumentGenerationRequest(
      messages: [ChatMessage(role: .user, content: "Hi")], registeredActions: ["bad action"])
  }
}
