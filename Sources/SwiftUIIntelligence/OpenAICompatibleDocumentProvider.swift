import Foundation

/// Optional OpenAI-compatible HTTPS backend. Model credentials stay with the caller.
/// POST {model, messages, response_format}; read choices[0].message.content as document JSON.
/// The session still performs the final strict validation.
public struct OpenAICompatibleDocumentProvider: DocumentGenerationProvider {
  public let endpoint: URL
  public let model: String
  private let apiKey: String
  private let session: URLSession
  private let maxResponseBytes: Int

  public init(endpoint: URL, apiKey: String, model: String) throws {
    try self.init(
      endpoint: endpoint, apiKey: apiKey, model: model,
      session: OpenAICompatibleDocumentProvider.makeSession(), maxResponseBytes: 65_536)
  }

  /// Test seam: the injected session keeps the request/response handling under test.
  init(endpoint: URL, apiKey: String, model: String, session: URLSession, maxResponseBytes: Int) throws {
    guard Self.isAllowed(endpoint) else {
      throw UIError(
        "Generation endpoint must use HTTPS, or loopback HTTP for a local model server, without embedded credentials."
      )
    }
    guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw UIError("An API key is required.")
    }
    guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw UIError("A model identifier is required.")
    }
    self.endpoint = endpoint
    self.apiKey = apiKey
    self.model = model
    self.session = session
    self.maxResponseBytes = maxResponseBytes
  }

  /// Plain HTTP is acceptable only for a loopback host, where the traffic stays on this Mac.
  static func isAllowed(_ endpoint: URL) -> Bool {
    guard let host = endpoint.host, !host.isEmpty, endpoint.user == nil, endpoint.password == nil else {
      return false
    }
    switch endpoint.scheme?.lowercased() {
    case "https": return true
    case "http": return isLoopback(host)
    default: return false
    }
  }

  static func isLoopback(_ host: String) -> Bool {
    let name = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
    if name == "localhost" || name == "::1" { return true }
    let octets = name.split(separator: ".", omittingEmptySubsequences: false)
    guard octets.count == 4, octets[0] == "127" else { return false }
    return octets.allSatisfy { Int($0).map { (0...255).contains($0) } ?? false }
  }

  static func makeSession() -> URLSession {
    // Ephemeral configuration does not persist chat responses or cookies to a shared cache.
    URLSession(configuration: URLSessionConfiguration.ephemeral)
  }

  /// The model needs the schema as text: this endpoint cannot express a guided-generation schema.
  static func body(for request: DocumentGenerationRequest, model: String) throws -> Data {
    let system = request.instructions + "\n\nJSON Schema:\n" + String(decoding: request.schemaJSON, as: UTF8.self)
    var messages: [[String: String]] = [["role": "system", "content": system]]
    messages += request.messages.map { ["role": $0.role.rawValue, "content": $0.content] }
    return try JSONSerialization.data(withJSONObject: [
      "model": model,
      "messages": messages,
      "stream": false,
      "temperature": 0,
      "response_format": ["type": "json_object"],
    ])
  }

  static func assistantContent(from data: Data) throws -> Data {
    guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      let choices = root["choices"] as? [[String: Any]],
      let message = choices.first?["message"] as? [String: Any],
      let content = message["content"] as? String,
      !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { throw UIError("Model response has no assistant content.") }
    return Data(content.utf8)
  }

  public func generate(_ request: DocumentGenerationRequest) async throws -> Data {
    var call = URLRequest(url: endpoint, timeoutInterval: 90)
    call.httpMethod = "POST"
    call.setValue("application/json", forHTTPHeaderField: "Content-Type")
    call.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    call.httpBody = try Self.body(for: request, model: model)
    let (bytes, response) = try await session.bytes(for: call)
    guard let http = response as? HTTPURLResponse else {
      throw UIError("Model endpoint did not return an HTTP response.")
    }
    guard (200...299).contains(http.statusCode) else {
      throw UIError("Model endpoint returned status \(http.statusCode).")
    }
    guard http.mimeType == "application/json" else {
      throw UIError("Model endpoint must return application/json.")
    }
    var data = Data()
    for try await byte in bytes {
      guard data.count < maxResponseBytes else { throw UIError("Model response exceeds 64 KiB.") }
      data.append(byte)
    }
    return try Self.assistantContent(from: data)
  }
}
