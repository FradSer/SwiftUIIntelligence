import Foundation

/// The library never interprets action names as code, URLs, selectors, or commands.
@MainActor public struct ActionRegistry {
  private var asyncCallbacks: [String: @MainActor (ActionEvent) async throws -> String] = [:]
  private let callbacks: [String: @MainActor () throws -> String]
  public var names: Set<String> { Set(callbacks.keys).union(asyncCallbacks.keys) }

  public init(_ callbacks: [String: @MainActor () throws -> String]) {
    self.callbacks = callbacks
  }

  /// Registering an ID grants exactly that host capability. No action runs during generation.
  public init(async callbacks: [String: @MainActor (ActionEvent) async throws -> String]) {
    self.callbacks = [:]; self.asyncCallbacks = callbacks
  }
  public func perform(_ event: ActionEvent) async throws -> String {
    if let callback = asyncCallbacks[event.action] { return try await callback(event) }
    return try perform(event.action)
  }

  public func perform(_ name: String) throws -> String {
    guard let callback = callbacks[name] else {
      throw UIError("Unknown action '\(name)'. No callback was executed.")
    }
    return try callback()
  }
}

public struct ActionEvent: Sendable {
  public let id: UUID
  public let action: String
  public let state: [String: StateValue]
  public init(action: String, state: [String: StateValue], id: UUID = UUID()) {
    self.id = id; self.action = action; self.state = state
  }
}
