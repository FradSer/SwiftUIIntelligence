import Foundation

/// Optional host-owned HTTPS backend. Model credentials remain on the server.
/// POST {messages,instructions,schema}; return the document itself as application/json.
public struct HTTPDocumentProvider: DocumentGenerationProvider {
  public let endpoint: URL
  public init(endpoint: URL) throws {
    guard endpoint.scheme == "https", endpoint.host != nil, endpoint.user == nil,
      endpoint.password == nil
    else {
      throw UIError("Generation backend must be an HTTPS URL without embedded credentials.")
    }
    self.endpoint = endpoint
  }
  public func generate(_ request: DocumentGenerationRequest) async throws -> Data {
    let schema = try JSONSerialization.jsonObject(with: request.schemaJSON)
    let messages = try JSONSerialization.jsonObject(with: request.conversationJSON())
    let body = try JSONSerialization.data(withJSONObject: [
      "messages": messages, "instructions": request.instructions, "schema": schema,
    ])
    var call = URLRequest(url: endpoint, timeoutInterval: 45)
    call.httpMethod = "POST"
    call.setValue("application/json", forHTTPHeaderField: "Content-Type")
    call.httpBody = body
    // Ephemeral configuration does not persist chat responses/cookies to a shared cache.
    let config = URLSessionConfiguration.ephemeral
    let session = URLSession(configuration: config)
    defer { session.invalidateAndCancel() }
    let (bytes, response) = try await session.bytes(for: call)
    guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
      throw UIError("Generation backend did not return a successful response.")
    }
    guard http.mimeType == "application/json" else {
      throw UIError("Generation backend must return application/json.")
    }
    var data = Data()
    for try await byte in bytes {
      guard data.count < 65_536 else { throw UIError("Generation response exceeds 64 KiB.") }
      data.append(byte)
    }
    return data
  }
}
