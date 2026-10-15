import Foundation
import Synchronization
import Testing

@testable import SwiftUIIntelligence

private let stubDocumentJSON = #"{"version":1,"root":{"id":"plan","type":"vstack","spacing":16,"children":[{"id":"heading","type":"text","text":"Volunteer plan","style":"title"}]},"floatingActions":[]}"#

/// Deterministic transport stub. The suite is serialized, so one slot is safe.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
  struct Stub: Sendable {
    let status: Int
    let contentType: String?
    let body: Data
  }

  private static let slot = Mutex<Stub?>(nil)

  static func install(_ stub: Stub?) { slot.withLock { $0 = stub } }

  static func stub() -> Stub? { slot.withLock { $0 } }

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    guard let stub = Self.stub() else {
      client?.urlProtocol(self, didFailWithError: UIError("No stub installed."))
      return
    }
    let headers = stub.contentType.map { ["Content-Type": $0] } ?? [:]
    let response = HTTPURLResponse(
      url: request.url ?? URL(string: "https://example.invalid")!, statusCode: stub.status,
      httpVersion: "HTTP/1.1", headerFields: headers)!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: stub.body)
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}

private func stubSession() -> URLSession {
  let config = URLSessionConfiguration.ephemeral
  config.protocolClasses = [StubURLProtocol.self]
  return URLSession(configuration: config)
}

private func openAIEnvelope(_ content: String) -> Data {
  let object: [String: Any] = [
    "model": "stub-model",
    "choices": [["index": 0, "finish_reason": "stop", "message": ["role": "assistant", "content": content]]],
  ]
  return try! JSONSerialization.data(withJSONObject: object)
}

@Suite(.serialized) struct OpenAICompatibleProviderTests {

  @Test func endpointPolicyAllowsHTTPSAndLoopbackOnly() throws {
    let https = URL(string: "https://models.example.com/v1/chat/completions")!
    let loopback = URL(string: "http://127.0.0.1:8317/v1/chat/completions")!
    let localhost = URL(string: "http://localhost:8317/v1/chat/completions")!
    let lan = URL(string: "http://10.10.0.195:8317/v1/chat/completions")!
    let credentialed = URL(string: "https://user:pass@models.example.com/v1/chat/completions")!

    #expect(throws: Never.self) { try OpenAICompatibleDocumentProvider(endpoint: https, apiKey: "k", model: "m") }
    #expect(throws: Never.self) { try OpenAICompatibleDocumentProvider(endpoint: loopback, apiKey: "k", model: "m") }
    #expect(throws: Never.self) { try OpenAICompatibleDocumentProvider(endpoint: localhost, apiKey: "k", model: "m") }
    #expect(throws: UIError.self) { try OpenAICompatibleDocumentProvider(endpoint: lan, apiKey: "k", model: "m") }
    #expect(throws: UIError.self) { try OpenAICompatibleDocumentProvider(endpoint: credentialed, apiKey: "k", model: "m") }
    #expect(throws: UIError.self) { try OpenAICompatibleDocumentProvider(endpoint: https, apiKey: "  ", model: "m") }
    #expect(throws: UIError.self) { try OpenAICompatibleDocumentProvider(endpoint: https, apiKey: "k", model: " ") }
  }

  @Test func requestCarriesInstructionsSchemaAndConversation() throws {
    let request = try DocumentGenerationRequest(
      messages: [
        .init(role: .user, content: "Plan the desk rota."),
        .init(role: .assistant, content: stubDocumentJSON),
        .init(role: .user, content: "Change the morning slot."),
      ],
      registeredActions: ["acknowledge"])
    let body = try OpenAICompatibleDocumentProvider.body(for: request, model: "deepseek-v4.1-flash")
    let root = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])

    #expect(root["model"] as? String == "deepseek-v4.1-flash")
    #expect(root["stream"] as? Bool == false)
    #expect((root["response_format"] as? [String: Any])?["type"] as? String == "json_object")

    let messages = try #require(root["messages"] as? [[String: Any]])
    #expect(messages.count == 4)
    #expect(messages.first?["role"] as? String == "system")
    let system = try #require(messages.first?["content"] as? String)
    #expect(system.contains(request.instructions))
    #expect(system.contains(String(decoding: request.schemaJSON, as: UTF8.self)))
    #expect(messages.dropFirst().map { $0["role"] as? String } == ["user", "assistant", "user"])
    #expect(messages.last?["content"] as? String == "Change the morning slot.")
  }

  @Test func assistantContentBecomesADecodableDocument() async throws {
    let provider = try OpenAICompatibleDocumentProvider(
      endpoint: URL(string: "https://models.example.com/v1/chat/completions")!, apiKey: "k",
      model: "stub-model", session: stubSession(), maxResponseBytes: 65_536)
    StubURLProtocol.install(.init(status: 200, contentType: "application/json", body: openAIEnvelope(stubDocumentJSON)))
    defer { StubURLProtocol.install(nil) }

    let request = try DocumentGenerationRequest(messages: [.init(role: .user, content: "Plan it.")])
    let raw = try await provider.generate(request)
    let document = try UIDocument.decode(raw, registeredActions: [])
    #expect(document.root.children.first?.text == "Volunteer plan")
  }

  @Test func transportAndEnvelopeFailuresAreRejected() async throws {
    let endpoint = URL(string: "https://models.example.com/v1/chat/completions")!
    func provider(max: Int = 65_536) throws -> OpenAICompatibleDocumentProvider {
      try OpenAICompatibleDocumentProvider(endpoint: endpoint, apiKey: "k", model: "m", session: stubSession(), maxResponseBytes: max)
    }
    let request = try DocumentGenerationRequest(messages: [.init(role: .user, content: "Plan it.")])

    StubURLProtocol.install(.init(status: 500, contentType: "application/json", body: openAIEnvelope(stubDocumentJSON)))
    await #expect(throws: UIError.self) { try await provider().generate(request) }

    StubURLProtocol.install(.init(status: 200, contentType: "text/html", body: openAIEnvelope(stubDocumentJSON)))
    await #expect(throws: UIError.self) { try await provider().generate(request) }

    StubURLProtocol.install(.init(status: 200, contentType: "application/json", body: Data(#"{"id":"x"}"#.utf8)))
    await #expect(throws: UIError.self) { try await provider().generate(request) }

    StubURLProtocol.install(.init(status: 200, contentType: "application/json", body: openAIEnvelope(String(repeating: "x", count: 4096))))
    await #expect(throws: UIError.self) { try await provider(max: 1024).generate(request) }

    StubURLProtocol.install(nil)
    await #expect(throws: (any Error).self) { try await provider().generate(request) }
  }
}
