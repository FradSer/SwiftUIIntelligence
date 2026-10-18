import Foundation
import Testing
import SwiftUIIntelligence
@_spi(Testing) import SwiftUIIntelligenceFoundationModels

@Test func finalRequirementsRejectStaticSubstitutes() throws {
  let requirements = DocumentRequirements(projectedComponents: [.table])
  let json = #"{"version":1,"root":{"id":"table","type":"table","columns":["Name"],"rows":[["Static"]]}}"#
  let document = try UIDocument.decode(Data(json.utf8), registeredActions: [])
  #expect(throws: UIError.self) { try requirements.validate(document) }
  try DocumentRequirements().validate(document)
}

@Test func projectedOnlyRequirementsRemainInPlannedScope() throws {
  let request = try DocumentGenerationRequest(messages: [.init(role: .user, content: "Show computed records.")],
    calculationSignatures: [.init(id: "compute", inputs: ["input": .number], outputs: ["output": .number])],
    requirements: .init(projectedComponents: [.table]))
  let plan = Data(#"{"selectedCapabilityIDs":["compute"],"componentTypes":["text"],"stateKinds":["number"]}"#.utf8)
  let data = try FoundationModelsDocumentProvider.plannedCalculationSchemaJSON(for: request, plan: plan)
  let schema = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
  #expect((schema["$defs"] as? [String: Any])?["table"] != nil)
}

@Test func unsupportedProjectedKindCannotPassFinalAcceptance() throws {
  let document = try UIDocument.decode(Data(#"{"version":1,"root":{"id":"text","type":"text","text":"Answer"}}"#.utf8), registeredActions: [])
  #expect(throws: UIError.self) { try DocumentRequirements(projectedComponents: [.text]).validate(document) }
}
