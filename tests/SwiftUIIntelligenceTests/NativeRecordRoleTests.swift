import Foundation
import SwiftUIIntelligence
@testable import SwiftUIIntelligenceFoundationModels
import Testing

@Test func sameCapabilityInputsKeepTheirAuthoredRecordRoles() throws {
  let signatures: [CalculationRegistry.Signature] = [.init(id: "compare", inputs: [:], outputs: [:],
    recordInputs: ["before": .init(fields: ["name": .text]), "after": .init(fields: ["name": .text])],
    recordOutputs: ["result": .init(fields: ["name": .text])])]
  let source = Data(#"{"scalarRoles":{"compare":{"inputs":{},"outputs":{}}},"recordInputs":{"compare":{"before":{"id":"old","schema":{"fields":{"name":"text"}},"rows":[{"id":"row","values":{"name":"Before"}}]},"after":{"id":"new","schema":{"fields":{"name":"text"}},"rows":[{"id":"row","values":{"name":"After"}}]}}},"recordOutputs":{"compare":{"result":{"id":"result"}}}}"#.utf8)
  let accepted = try NativeCalculationData.normalizeRoleData(source, signatures: signatures)
  #expect(accepted.recordInputRoles["compare"] == ["before": "old", "after": "new"])
  for swapped in [false, true] {
    let inputs = swapped ? ["before": "new", "after": "old"] : ["before": "old", "after": "new"]
    let bindings = try JSONSerialization.data(withJSONObject: ["calculations": [["id": "comparison", "capability": "compare", "inputs": [:], "outputs": [:], "recordInputs": inputs, "recordOutputs": ["result": "result"]]]])
    if swapped {
      #expect(throws: UIError.self) { try NativeCalculationData.normalizeBindings(bindings, data: accepted, signatures: signatures) }
    } else { _ = try NativeCalculationData.normalizeBindings(bindings, data: accepted, signatures: signatures) }
  }
}

@Test func identicalRecordSchemasCannotSwapAuthoredInputRoles() throws {
  let signatures: [CalculationRegistry.Signature] = ["first", "second"].map {
    .init(id: $0, inputs: [:], outputs: [:], recordInputs: ["products": .init(fields: ["name": .text])], recordOutputs: ["result": .init(fields: ["name": .text])])
  }
  let source = Data(#"{"state":[],"recordInputs":{"first":{"products":{"id":"first-products","schema":{"fields":{"name":"text"}},"rows":[{"id":"row","values":{"name":"First"}}]}},"second":{"products":{"id":"second-products","schema":{"fields":{"name":"text"}},"rows":[{"id":"row","values":{"name":"Second"}}]}}},"recordOutputs":{"first":{"result":{"id":"first-result"}},"second":{"result":{"id":"second-result"}}}}"#.utf8)
  let accepted = try NativeCalculationData.normalizeData(source, signatures: signatures)
  let schema = try JSONSerialization.jsonObject(with: NativeCalculationData.bindingSchema(data: accepted, signatures: signatures)) as! [String: Any]
  let properties = schema["properties"] as! [String: [String: Any]]
  let items = properties["calculations"]!["items"] as! [String: Any]
  let variants = items["anyOf"] as! [[String: Any]]
  for variant in variants {
    let fields = variant["properties"] as! [String: [String: Any]]
    let capability = (fields["capability"]!["enum"] as! [String])[0]
    let inputFields = fields["recordInputs"]!["properties"] as! [String: [String: Any]]
    #expect(inputFields["products"]!["enum"] as? [String] == [capability + "-products"])
  }
  let bindings = Data(#"{"calculations":[{"id":"one","capability":"first","inputs":{},"outputs":{},"recordInputs":{"products":"second-products"},"recordOutputs":{"result":"first-result"}},{"id":"two","capability":"second","inputs":{},"outputs":{},"recordInputs":{"products":"first-products"},"recordOutputs":{"result":"second-result"}}]}"#.utf8)
  #expect(throws: UIError.self) { try NativeCalculationData.normalizeBindings(bindings, data: accepted, signatures: signatures) }
}
