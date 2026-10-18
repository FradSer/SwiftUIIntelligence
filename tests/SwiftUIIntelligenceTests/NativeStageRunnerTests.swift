import Foundation
@testable import SwiftUIIntelligenceFoundationModels
import Testing

@Suite struct NativeStageRunnerTests {
  private struct Rejected: Error, LocalizedError {
    var errorDescription: String? { "Rejected candidate" }
  }

  // Given accepted data and bindings, when layout fails, then only layout runs again.
  @Test func layoutRetryPreservesAcceptedStages() async throws {
    var calls = [0, 0, 0]
    let result = try await NativeStageRunner.run(
      generateData: { attempt, feedback in
        calls[0] += 1
        #expect(attempt == 1 && feedback.isEmpty)
        return Data("exact source facts".utf8)
      },
      generateBindings: { data, attempt, feedback in
        calls[1] += 1
        #expect(data == Data("exact source facts".utf8))
        #expect(attempt == 1 && feedback.isEmpty)
        return data + Data("; accepted bindings".utf8)
      },
      generateLayout: { declarations, attempt, feedback in
        calls[2] += 1
        #expect(declarations == Data("exact source facts; accepted bindings".utf8))
        #expect(attempt == calls[2])
        if attempt == 1 {
          #expect(feedback.isEmpty)
          throw Rejected()
        }
        #expect(feedback.contains("layout") && feedback.contains("Rejected candidate"))
        return declarations
      })
    #expect(result == Data("exact source facts; accepted bindings".utf8))
    #expect(calls == [1, 1, 2])
  }

  // Given accepted data, when bindings fail, then binding feedback cannot reach data generation.
  @Test func bindingRetryPreservesDataAndReceivesFeedback() async throws {
    var calls = [0, 0, 0]
    _ = try await NativeStageRunner.run(
      generateData: { _, feedback in
        calls[0] += 1
        #expect(feedback.isEmpty)
        return "unchanged source"
      },
      generateBindings: { data, attempt, feedback in
        calls[1] += 1
        #expect(data == "unchanged source")
        if attempt == 1 { throw Rejected() }
        #expect(feedback.contains("bindings") && feedback.contains("Rejected candidate"))
        return Data(data.utf8)
      },
      generateLayout: { declarations, attempt, feedback in
        calls[2] += 1
        #expect(attempt == 1 && feedback.isEmpty)
        return declarations
      })
    #expect(calls == [1, 2, 1])
  }

  // Given invalid candidates at every stage, when retries succeed last, then calls total nine.
  @Test func eachStageHasThreeAttempts() async throws {
    var calls = [0, 0, 0]
    _ = try await NativeStageRunner.run(
      generateData: { attempt, feedback in
        calls[0] += 1
        #expect(feedback.isEmpty == (attempt == 1))
        if attempt < 3 { throw Rejected() }
        return 42
      },
      generateBindings: { data, attempt, feedback in
        calls[1] += 1
        #expect(data == 42)
        #expect(feedback.isEmpty == (attempt == 1))
        if attempt < 3 { throw Rejected() }
        return data
      },
      generateLayout: { declarations, attempt, feedback in
        calls[2] += 1
        #expect(declarations == 42)
        #expect(feedback.isEmpty == (attempt == 1))
        if attempt < 3 { throw Rejected() }
        return declarations
      })
    #expect(calls == [3, 3, 3])
  }

  // Given a stage that never succeeds, when its budget ends, then later stages cannot run.
  @Test(arguments: ["declarations", "bindings", "layout"])
  func exhaustionNamesFailedStage(stage: String) async throws {
    var calls = [0, 0, 0]
    do {
      _ = try await NativeStageRunner.run(
        generateData: { _, _ in
          calls[0] += 1
          if stage == "declarations" { throw Rejected() }
          return 1
        },
        generateBindings: { data, _, _ in
          calls[1] += 1
          if stage == "bindings" { throw Rejected() }
          return data
        },
        generateLayout: { declarations, _, _ in
          calls[2] += 1
          if stage == "layout" { throw Rejected() }
          return declarations
        })
      Issue.record("Generation must fail after three rejected candidates.")
    } catch {
      #expect(error.localizedDescription.contains("during \(stage) after three attempts"))
    }
    let expected = stage == "declarations" ? [3, 0, 0] : stage == "bindings" ? [1, 3, 0] : [1, 1, 3]
    #expect(calls == expected)
  }

  private actor SuspensionGate {
    var started: CheckedContinuation<Void, Never>?
    var release: CheckedContinuation<Void, Never>?
    var entered = false
    func waitUntilEntered() async {
      if entered { return }
      await withCheckedContinuation { started = $0 }
    }
    func suspend() async {
      entered = true
      started?.resume(); started = nil
      await withCheckedContinuation { release = $0 }
    }
    func resume() { release?.resume(); release = nil }
  }

  @Test func externalCancellationDuringSuspendedStageCannotAdvance() async {
    let gate = SuspensionGate()
    let task = Task {
      do {
        _ = try await NativeStageRunner.run(generateData: { _, _ in
          await gate.suspend()
          return 1
        }, generateBindings: { value, _, _ in
          Issue.record("Cancellation must stop before bindings.")
          return value
        }, generateLayout: { value, _, _ in value })
        Issue.record("Cancellation must prevent acceptance.")
      } catch { #expect(error is CancellationError) }
    }
    await gate.waitUntilEntered()
    task.cancel()
    await gate.resume()
    await task.value
  }

  // Given cancellation before or during a stage, when control returns, then no later stage runs.
  @Test(arguments: ["before", "data", "bindings", "layout", "throw"])
  func cancellationStopsWithoutRetry(point: String) async throws {
    let task = Task {
      var calls = [0, 0, 0]
      if point == "before" { withUnsafeCurrentTask { $0?.cancel() } }
      do {
        _ = try await NativeStageRunner.run(
          generateData: { _, _ in
            calls[0] += 1
            if point == "data" { withUnsafeCurrentTask { $0?.cancel() } }
            if point == "throw" { throw CancellationError() }
            return 1
          },
          generateBindings: { data, _, _ in
            calls[1] += 1
            if point == "bindings" { withUnsafeCurrentTask { $0?.cancel() } }
            return data
          },
          generateLayout: { declarations, _, _ in
            calls[2] += 1
            withUnsafeCurrentTask { $0?.cancel() }
            return declarations
          })
        Issue.record("Cancelled generation must not return an accepted result.")
      } catch {
        #expect(error is CancellationError)
      }
      return calls
    }
    let calls = await task.value
    let expected = point == "before" ? [0, 0, 0] : point == "bindings" ? [1, 1, 0] : point == "layout" ? [1, 1, 1] : [1, 0, 0]
    #expect(calls == expected)
  }
}
