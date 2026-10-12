import Foundation
import SwiftUIIntelligence

private struct JSONKey: CodingKey {
  let stringValue: String
  var intValue: Int? { nil }
  init?(stringValue: String) { self.stringValue = stringValue }
  init?(intValue: Int) { return nil }
}

func checkKeys(_ decoder: any Decoder, allowed: Set<String>) throws {
  let keys = try decoder.container(keyedBy: JSONKey.self).allKeys.map(\.stringValue)
  if let unknown = keys.sorted().first(where: { !allowed.contains($0) }) {
    throw UIError("Unknown field '\(unknown)' at \(location(decoder.codingPath)).")
  }
}

private func location(_ path: [any CodingKey]) -> String {
  path.isEmpty ? "$" : "$." + path.map(\.stringValue).joined(separator: ".")
}

func validIdentifier(_ value: String) -> Bool {
  !value.isEmpty && value.utf8.count <= 64
    && value.utf8.allSatisfy {
      (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0)
        || [45, 46, 95].contains($0)
    }
}
