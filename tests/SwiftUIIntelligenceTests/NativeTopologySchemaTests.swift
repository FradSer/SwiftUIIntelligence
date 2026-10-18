import Foundation
import SwiftUIIntelligence
@_spi(Testing) @testable import SwiftUIIntelligenceFoundationModels
import Testing

@Test func topologyPayloadGuidancePreservesRequiredAndOptionalProperties() throws {
  for kind: UINode.Kind in [.vstack, .hstack, .grid, .section, .form, .text, .control, .metric, .list, .table, .chart, .timeline] {
    let data = try NativeTopologySchema.payload(kind: kind, id: "authored-node")
    #expect(try FoundationModelsDocumentProvider.validateNativeLayoutSchema(data))
    let root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let fields = try #require(root["properties"] as? [String: [String: Any]])
    let required = try #require(root["required"] as? [String])
    #expect(fields["id"]?["enum"] as? [String] == ["authored-node"])
    #expect(!required.contains("spacing"))
    if kind == .grid { #expect(required.contains("columnCount")) }
    if kind == .section || kind == .form { #expect(required.contains("title")); #expect(!required.contains("icon")) }
    if let modes = fields["mode"]?["enum"] as? [String] {
      #expect(required.contains("purpose"))
      #expect(modes == ([UINode.Kind.list, .table, .chart, .timeline].contains(kind) ? ["static", "records"] : ["static"]))
    }
  }
}

@Test func topologyBatchSchemaIsNonrecursiveAndNativeConvertible() throws {
  let data = try NativeTopologySchema.batch(availableKinds: [.vstack, .section, .table, .text])
  let root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
  #expect(root["$defs"] == nil)
  #expect(!String(decoding: data, as: UTF8.self).contains("$ref"))
  let fields = try #require(root["properties"] as? [String: [String: Any]])
  #expect(fields["nodes"]?["maxItems"] as? Int == 16)
  let node = try #require(fields["nodes"]?["items"] as? [String: Any])
  #expect(node["required"] as? [String] == ["id", "kind", "parentID"])
  let nodeFields = try #require(node["properties"] as? [String: [String: Any]])
  #expect(nodeFields["kind"]?["enum"] as? [String] == ["section", "table", "text", "vstack"])
  #expect(try FoundationModelsDocumentProvider.validateNativeLayoutSchema(data))
}
