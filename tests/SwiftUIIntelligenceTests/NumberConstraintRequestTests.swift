import Foundation
import SwiftUIIntelligence
import Testing

@Test func requestPublishesHostNumericDomainsWithoutSupplyingValues() throws {
  let signature = CalculationRegistry.Signature(id: "scale", inputs: ["factor": .number], outputs: ["answer": .number],
    inputNumberConstraints: ["factor": .init(minimum: 1, maximum: 100, integer: true, step: 1)])
  let request = try DocumentGenerationRequest(messages: [.init(role: .user, content: "Use supplied factor")], calculationSignatures: [signature])
  #expect(request.calculationDeclarationInstructions.contains("inputNumberConstraints"))
  #expect(request.calculationDeclarationInstructions.contains("100"))
}

@Test func requestRejectsConstraintsForNonNumericOrMissingInputs() throws {
  for inputs: [String: CalculationRegistry.ValueKind] in [["factor": .text], ["other": .number]] {
    let signature = CalculationRegistry.Signature(id: "scale", inputs: inputs, outputs: ["answer": .number],
      inputNumberConstraints: ["factor": .init(minimum: 1, maximum: 100, integer: true)])
    #expect(throws: UIError.self) {
      try DocumentGenerationRequest(messages: [.init(role: .user, content: "Use supplied factor")], calculationSignatures: [signature])
    }
  }
}
