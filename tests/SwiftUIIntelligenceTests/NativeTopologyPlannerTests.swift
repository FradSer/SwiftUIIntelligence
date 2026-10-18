import Foundation
import SwiftUIIntelligence
@_spi(Testing) @testable import SwiftUIIntelligenceFoundationModels
import Testing

@Suite struct NativeTopologyPlannerTests {
  private actor Calls {
    var values: [String] = []
    func add(_ value: String) { values.append(value) }
    func snapshot() -> [String] { values }
  }

  @Test func incompleteRequiredKindsRejectBeforePayloadCalls() async throws {
    let calls = Calls()
    await #expect(throws: UIError.self) {
      try await NativeTopologyPlanner.run(availableKinds: [.hstack, .table, .chart],
        requirements: .init(projectedComponents: [.table, .chart]), generateBatch: { _, _, _ in
          Data(#"{"nodes":[{"id":"root","parentID":"","kind":"hstack"}],"complete":true}"#.utf8)
        }, generatePayload: { _, _, _ in
          await calls.add("payload")
          return Data(#"{"id":"root"}"#.utf8)
        })
    }
    #expect(await calls.snapshot().isEmpty)
  }

  @Test func insufficientControlCountRejectsBeforePayloadCalls() async throws {
    let calls = Calls()
    await #expect(throws: UIError.self) {
      try await NativeTopologyPlanner.run(availableKinds: [.control],
        requirements: .init(controls: [.toggle, .stepper]), generateBatch: { _, _, _ in
          Data(#"{"nodes":[{"id":"input","parentID":"","kind":"control"}],"complete":true}"#.utf8)
        }, generatePayload: { _, _, _ in
          await calls.add("payload")
          return Data(#"{"id":"input","mode":"static","purpose":"Input"}"#.utf8)
        })
    }
    #expect(await calls.snapshot().isEmpty)
  }

  // Given cross-batch nodes, when complete, then payloads see the frozen authored order.
  @Test func preservesCrossBatchOrderModesAndConvertibleSchemas() async throws {
    let calls = Calls()
    let first = #"[{"id":"root","parentID":"","kind":"vstack"},{"id":"group","parentID":"root","kind":"section"},{"id":"reference","parentID":"root","kind":"table"}]"#
    let second = #"[{"id":"result","parentID":"group","kind":"table"},{"id":"note","parentID":"group","kind":"text"}]"#
    let frozen = String(first.dropLast()) + "," + String(second.dropFirst())
    let payloads = ["root": #"{"id":"root"}"#, "group": #"{"id":"group","title":"Exact group","spacing":7.5}"#,
      "reference": #"{"id":"reference","mode":"static","purpose":"Supplied table"}"#,
      "result": #"{"id":"result","mode":"records","purpose":"Computed rows"}"#,
      "note": #"{"id":"note","mode":"static","purpose":"Exact note"}"#]
    @Sendable func nodes(_ data: Data) throws -> NSArray {
      try #require(JSONSerialization.jsonObject(with: data) as? NSArray)
    }
    let plan = try await NativeTopologyPlanner.run(availableKinds: [.vstack, .section, .table, .text],
      requirements: .init(projectedComponents: [.table]), generateBatch: { schema, prefix, index in
        #expect(try FoundationModelsDocumentProvider.validateNativeLayoutSchema(schema))
        #expect(index == 1 || index == 2)
        let expectedPrefix = try nodes(Data((index == 1 ? "[]" : first).utf8))
        #expect(try nodes(prefix) == expectedPrefix)
        await calls.add("batch\(index)")
        return Data("{\"nodes\":\(index == 1 ? first : second),\"complete\":\(index == 2)}".utf8)
      }, generatePayload: { node, schema, topology in
        #expect(try FoundationModelsDocumentProvider.validateNativeLayoutSchema(schema))
        let expectedFrozen = try nodes(Data(frozen.utf8))
        #expect(try nodes(topology) == expectedFrozen)
        await calls.add(node.id)
        return Data(try #require(payloads[node.id]).utf8)
      })
    #expect(await calls.snapshot() == ["batch1", "batch2", "root", "group", "reference", "result", "note"])
    let validated = try NativeLayoutSlots.validatePlan(plan, requirements: .init(projectedComponents: [.table]))
    #expect(validated.slots.map(\.id) == ["result", "note", "reference"])
    #expect(validated.slots.map(\.projected) == [true, false, false])
    let object = try #require(JSONSerialization.jsonObject(with: plan) as? [String: Any])
    let root = try #require(object["root"] as? [String: Any])
    #expect(root["spacing"] == nil)
    let children = try #require(root["children"] as? [[String: Any]])
    #expect(children.compactMap { $0["id"] as? String } == ["group", "reference"])
    #expect(children[0]["title"] as? String == "Exact group")
    #expect(children[0]["spacing"] as? Double == 7.5)
  }

  private struct Rejected: Error, LocalizedError {
    var errorDescription: String? { "SECRET generated content" }
  }

  // Given a failed batch, when generation throws or validation rejects it, then no payload runs.
  @Test(arguments: [false, true])
  func failedBatchAbortsWithoutRetry(invalid: Bool) async {
    let calls = Calls()
    do {
      _ = try await NativeTopologyPlanner.run(availableKinds: [.vstack, .text], requirements: .init(),
        generateBatch: { _, _, index in
          await calls.add("batch\(index)")
          if index == 1 { return Data(#"{"nodes":[{"id":"root","parentID":"","kind":"vstack"}],"complete":false}"#.utf8) }
          if invalid { return Data(#"{"nodes":[{"id":"note","parentID":"missing","kind":"text"}],"complete":true}"#.utf8) }
          throw Rejected()
        }, generatePayload: { _, _, _ in await calls.add("payload"); return Data() })
      Issue.record("A failed batch must abort planning.")
    } catch {
      #expect(error.localizedDescription.contains("batch 2"))
      #expect(!error.localizedDescription.contains("SECRET"))
    }
    #expect(await calls.snapshot() == ["batch1", "batch2"])
  }

  // Given a payload failure, when the second call throws, then later payloads do not run.
  @Test func payloadFailureAbortsWithoutRetry() async {
    let calls = Calls()
    do {
      _ = try await NativeTopologyPlanner.run(availableKinds: [.vstack, .text], requirements: .init(),
        generateBatch: { _, _, _ in
          await calls.add("batch")
          return Data(#"{"nodes":[{"id":"root","parentID":"","kind":"vstack"},{"id":"first","parentID":"root","kind":"text"},{"id":"later","parentID":"root","kind":"text"}],"complete":true}"#.utf8)
        }, generatePayload: { node, _, _ in
          await calls.add(node.id)
          if node.id == "first" { throw Rejected() }
          return Data(#"{"id":"root"}"#.utf8)
        })
      Issue.record("A payload failure must abort planning.")
    } catch {
      #expect(error.localizedDescription.contains("payload 2"))
      #expect(!error.localizedDescription.contains("SECRET"))
    }
    #expect(await calls.snapshot() == ["batch", "root", "first"])
  }

  // Given requirements or payloads that fail final validation, then no plan is returned.
  @Test(arguments: [false, true])
  func finalAssemblyValidationIsRequired(invalidPayload: Bool) async {
    let calls = Calls()
    do {
      _ = try await NativeTopologyPlanner.run(availableKinds: [.text],
        requirements: invalidPayload ? .init() : .init(projectedComponents: [.table]),
        generateBatch: { _, _, _ in
          await calls.add("batch")
          return Data(#"{"nodes":[{"id":"note","parentID":"","kind":"text"}],"complete":true}"#.utf8)
        }, generatePayload: { _, _, _ in
          await calls.add("payload")
          return Data((invalidPayload ? #"{"id":"other","mode":"static","purpose":"Exact"}"# : #"{"id":"note","mode":"static","purpose":"Exact"}"#).utf8)
        })
      Issue.record("Final assembly must validate payloads and requirements.")
    } catch { #expect(error is UIError) }
    #expect(await calls.snapshot() == (invalidPayload ? ["batch", "payload"] : ["batch"]))
  }

  // Given eight full batches, when completion is explicit, then calls stop at eight plus 128.
  @Test(arguments: [false, true])
  func maximumBatchAndPayloadCallsAreBounded(complete: Bool) async throws {
    let calls = Calls()
    do {
      _ = try await NativeTopologyPlanner.run(availableKinds: [.vstack], requirements: .init(),
        generateBatch: { _, prefix, index in
          await calls.add("batch")
          let accepted = try #require(JSONSerialization.jsonObject(with: prefix) as? [[String: String]])
          #expect(accepted.count == (index - 1) * 16)
          let entries = (0..<16).map { offset -> [String: String] in
            let number = (index - 1) * 16 + offset
            // A shallow authored tree with four branch containers keeps all limits valid.
            let parent = number == 0 ? "" : number < 5 ? "n0" : "n\(1 + (number - 5) / 31)"
            return ["id": "n\(number)", "parentID": parent, "kind": "vstack"]
          }
          return try JSONSerialization.data(withJSONObject: ["nodes": entries, "complete": complete && index == 8])
        }, generatePayload: { node, _, frozen in
          await calls.add("payload")
          let nodes = try #require(JSONSerialization.jsonObject(with: frozen) as? [[String: String]])
          #expect(nodes.count == 128)
          return try JSONSerialization.data(withJSONObject: ["id": node.id])
        })
      #expect(complete)
    } catch {
      #expect(!complete)
      #expect(error.localizedDescription.contains("batch 8"))
    }
    let values = await calls.snapshot()
    #expect(values.filter { $0 == "batch" }.count == 8)
    #expect(values.filter { $0 == "payload" }.count == (complete ? 128 : 0))
  }

  private actor Gate {
    private var entered = false
    private var entry: CheckedContinuation<Void, Never>?
    private var release: CheckedContinuation<Void, Never>?
    func waitUntilEntered() async {
      if entered { return }
      await withCheckedContinuation { entry = $0 }
    }
    func suspend() async {
      if entered { return }
      entered = true
      entry?.resume(); entry = nil
      await withCheckedContinuation { release = $0 }
    }
    func resume() { release?.resume(); release = nil }
  }

  // Given suspended generation, when cancelled externally, then no later call or plan is accepted.
  @Test(arguments: ["incompleteBatch", "completeBatch", "firstPayload", "lastPayload"])
  func cancellationDuringGenerationStops(point: String) async {
    let calls = Calls()
    let gate = Gate()
    let task = Task {
      do {
        _ = try await NativeTopologyPlanner.run(availableKinds: [.vstack, .text], requirements: .init(),
          generateBatch: { _, _, _ in
            await calls.add("batch")
            if point == "incompleteBatch" || point == "completeBatch" { await gate.suspend() }
            return Data("{\"nodes\":[{\"id\":\"root\",\"parentID\":\"\",\"kind\":\"vstack\"},{\"id\":\"note\",\"parentID\":\"root\",\"kind\":\"text\"}],\"complete\":\(point != "incompleteBatch")}".utf8)
          }, generatePayload: { node, _, _ in
            await calls.add(node.id)
            if (point == "firstPayload" && node.id == "root") || (point == "lastPayload" && node.id == "note") {
              await gate.suspend()
            }
            return Data((node.id == "root" ? #"{"id":"root"}"# : #"{"id":"note","mode":"static","purpose":"Exact"}"#).utf8)
          })
        Issue.record("Cancelled generation must not return a plan.")
      } catch { #expect(error is CancellationError) }
    }
    await gate.waitUntilEntered()
    task.cancel()
    await gate.resume()
    await task.value
    let expected = point == "firstPayload" ? ["batch", "root"] : point == "lastPayload" ? ["batch", "root", "note"] : ["batch"]
    #expect(await calls.snapshot() == expected)
  }

  // Given a cancelled task, when planning starts, then neither generator runs.
  @Test func cancelledBeforeStartMakesNoCalls() async {
    let calls = Calls()
    let task = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      do {
        _ = try await NativeTopologyPlanner.run(availableKinds: [.text], requirements: .init(),
          generateBatch: { _, _, _ in await calls.add("batch"); return Data() },
          generatePayload: { _, _, _ in await calls.add("payload"); return Data() })
        Issue.record("Cancelled planning must not return a plan.")
      } catch { #expect(error is CancellationError) }
    }
    await task.value
    #expect(await calls.snapshot().isEmpty)
  }
}
