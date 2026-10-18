import CoreFoundation
import Foundation
import SwiftUIIntelligence

/// Experimental, ordered topology state. This type does not assemble a document.
struct NativeLayoutTopology: Sendable {
  enum ParentPolicy: Sendable {
    case orderedPrefix
    case snapshotContainers
  }

  struct Node: Sendable, Equatable {
    let id: String
    let parentID: String
    let kind: UINode.Kind
  }

  private static let containers: Set<UINode.Kind> = [.vstack, .hstack, .grid, .section, .form]
  private static let leaves: Set<UINode.Kind> = [.text, .control, .metric, .list, .table, .chart, .timeline]

  private let availableKinds: Set<UINode.Kind>
  private let parentPolicy: ParentPolicy
  private(set) var nodes: [Node] = []
  private(set) var isComplete = false
  private var batchCount = 0

  init(availableKinds: Set<UINode.Kind>, parentPolicy: ParentPolicy = .orderedPrefix) throws {
    guard !availableKinds.isEmpty, availableKinds.isSubset(of: Self.containers.union(Self.leaves)) else {
      throw UIError("Topology requires a nonempty set of supported kinds.")
    }
    self.availableKinds = availableKinds
    self.parentPolicy = parentPolicy
  }

  mutating func accept(_ data: Data) throws {
    guard !isComplete, batchCount < 8 else { throw UIError("Topology has completed or reached eight batches.") }
    let decoded: Any
    do { decoded = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) }
    catch { throw UIError("Topology requires valid JSON.") }
    try Self.validateJSONSyntax(data)
    guard let object = decoded as? [String: Any], Set(object.keys) == ["nodes", "complete"],
      let entries = object["nodes"] as? [[String: Any]], let flag = object["complete"] as? NSNumber,
      CFGetTypeID(flag) == CFBooleanGetTypeID() else {
      throw UIError("Topology requires nodes and complete.")
    }
    let complete = flag.boolValue
    let maximumNodes = parentPolicy == .snapshotContainers ? 113 : 128
    guard entries.count <= 16, nodes.count + entries.count <= maximumNodes, !entries.isEmpty || (complete && !nodes.isEmpty),
      batchCount < 7 || complete else {
      throw UIError("A batch accepts at most 16 entries and the eighth batch must complete the topology.")
    }
    let snapshotParents = Set(nodes.filter { Self.containers.contains($0.kind) }.map(\.id))
    if parentPolicy == .snapshotContainers {
      guard nodes.isEmpty ? entries.count == 1 : !snapshotParents.isEmpty else {
        throw UIError("Snapshot topology requires one root or prior containers.")
      }
    }
    var candidate = nodes
    for entry in entries {
      guard Set(entry.keys) == ["id", "parentID", "kind"],
        let id = entry["id"] as? String, Self.validID(id), !candidate.contains(where: { $0.id == id }),
        let parentID = entry["parentID"] as? String, let rawKind = entry["kind"] as? String,
        let kind = UINode.Kind(rawValue: rawKind), availableKinds.contains(kind) else {
        throw UIError("Topology nodes require unique valid IDs and available kinds.")
      }
      if candidate.isEmpty {
        guard parentID.isEmpty else { throw UIError("The first node must be the sole root.") }
      } else {
        guard parentPolicy != .snapshotContainers || snapshotParents.contains(parentID) else {
          throw UIError("A snapshot parent must be a previously accepted container.")
        }
        guard let parent = candidate.first(where: { $0.id == parentID }), Self.containers.contains(parent.kind) else {
          throw UIError("A parent must be an earlier container.")
        }
      }
      var depth = 1
      var ancestorID = parentID
      while let ancestor = candidate.first(where: { $0.id == ancestorID }) {
        depth += 1
        ancestorID = ancestor.parentID
      }
      guard parentID.isEmpty || candidate.filter({ $0.parentID == parentID }).count < 32 else {
        throw UIError("A topology container accepts at most 32 children.")
      }
      guard !Self.leaves.contains(kind) || candidate.filter({ Self.leaves.contains($0.kind) }).count < 32 else {
        throw UIError("Topology accepts at most 32 leaf slots.")
      }
      let maximumDepth = parentPolicy == .snapshotContainers ? 8 : 12
      guard depth <= maximumDepth else { throw UIError("Topology exceeds its depth limit.") }
      candidate.append(Node(id: id, parentID: parentID, kind: kind))
    }
    guard parentPolicy != .snapshotContainers || complete || candidate.contains(where: { Self.containers.contains($0.kind) }) else {
      throw UIError("An incomplete snapshot topology requires a container.")
    }
    nodes = candidate
    isComplete = complete
    batchCount += 1
  }

  /// Reject duplicate keys and trailing commas before using Foundation-parsed objects.
  /// This check covers experimental topology batches and node payloads, not the core document decoder.
  static func validateJSONSyntax(_ data: Data) throws {
    // Foundation also accepts UTF-16 and UTF-32 JSON. Normalize those bytes for this scan.
    let encodings: [String.Encoding] = [.utf8, .utf32, .utf32BigEndian, .utf32LittleEndian, .utf16, .utf16BigEndian, .utf16LittleEndian]
    let text = encodings.lazy.compactMap { String(data: data, encoding: $0) }.first { value in
      guard !value.unicodeScalars.contains(where: { $0.value == 0 }) else { return false }
      return (try? JSONSerialization.jsonObject(with: Data(value.utf8), options: [.fragmentsAllowed])) != nil
    }
    guard let text else { throw UIError("Topology requires a supported JSON encoding.") }
    let bytes = Array(text.utf8)
    var objects: [Set<String>] = []
    var index = 0
    while index < bytes.count {
      switch bytes[index] {
      case 44:
        var next = index + 1
        while next < bytes.count && [9, 10, 13, 32].contains(bytes[next]) { next += 1 }
        guard next < bytes.count, bytes[next] != 125, bytes[next] != 93 else {
          throw UIError("Topology JSON cannot contain trailing commas.")
        }
      case 123: objects.append([])
      case 125: objects.removeLast()
      case 34:
        let start = index
        index += 1
        while index < bytes.count {
          if bytes[index] == 92 { index += 2; continue }
          if bytes[index] == 34 { break }
          index += 1
        }
        let end = index + 1
        var next = end
        while next < bytes.count && [9, 10, 13, 32].contains(bytes[next]) { next += 1 }
        if next < bytes.count && bytes[next] == 58 {
          // The JSON parser has already checked string syntax and object structure.
          guard let key = try JSONSerialization.jsonObject(with: Data(bytes[start..<end]), options: [.fragmentsAllowed]) as? String,
            !objects.isEmpty, objects[objects.count - 1].insert(key).inserted else {
            throw UIError("Topology JSON cannot contain duplicate keys.")
          }
        }
      default: break
      }
      index += 1
    }
  }

  private static func validID(_ value: String) -> Bool {
    !value.isEmpty && value.utf8.count <= 64 && value.utf8.allSatisfy {
      (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || [45, 46, 95].contains($0)
    }
  }
}
