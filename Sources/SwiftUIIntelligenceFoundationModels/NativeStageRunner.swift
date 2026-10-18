import Foundation

/// Each closure returns only a validated value. Accepted stages never run again.
enum NativeStageRunner {
  // Three calls per stage bound generation to nine calls, excluding the planner.
  static let maximumAttemptsPerStage = 3

  static func run<Source, Declarations, Output>(
    generateData: (Int, String) async throws -> Source,
    generateBindings: (Source, Int, String) async throws -> Declarations,
    generateLayout: (Declarations, Int, String) async throws -> Output,
    onFailure: (String, Int, any Error) -> Void = { _, _, _ in }
  ) async throws -> Output {
    let data = try await accepted(stage: "declarations", onFailure: onFailure, generate: generateData)
    let declarations = try await accepted(stage: "bindings", onFailure: onFailure) { attempt, feedback in
      try await generateBindings(data, attempt, feedback)
    }
    return try await accepted(stage: "layout", onFailure: onFailure) { attempt, feedback in
      try await generateLayout(declarations, attempt, feedback)
    }
  }

  private static func accepted<Value>(stage: String,
    onFailure: (String, Int, any Error) -> Void,
    generate: (Int, String) async throws -> Value
  ) async throws -> Value {
    var feedback = ""
    for attempt in 1...maximumAttemptsPerStage {
      try Task.checkCancellation()
      do {
        let value = try await generate(attempt, feedback)
        try Task.checkCancellation()
        return value
      } catch {
        onFailure(stage, attempt, error)
        if error is CancellationError || Task.isCancelled { throw CancellationError() }
        if attempt == maximumAttemptsPerStage {
          throw StageFailure(stage: stage, reason: error.localizedDescription)
        }
        feedback = "Previous \(stage) failed validation: \(error.localizedDescription). Correct only this stage. Preserve supplied facts and accepted declarations."
      }
    }
    preconditionFailure("The stage must return or throw within its attempt limit.")
  }

  private struct StageFailure: LocalizedError {
    let stage: String
    let reason: String
    var errorDescription: String? {
      "Native calculated document generation failed during \(stage) after three attempts: \(reason)"
    }
  }
}
