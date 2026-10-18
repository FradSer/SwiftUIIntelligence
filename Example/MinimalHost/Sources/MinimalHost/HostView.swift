import SwiftUIIntelligence
import SwiftUIIntelligenceFoundationModels
import SwiftUI

/// Builds as a separate package using only exported public APIs.
public struct HostView: View {
  private let calculations: CalculationRegistry
  public init() {
    calculations = try! CalculationRegistry([
        .init(id: "double", inputs: ["input": .number], outputs: ["output": .number]) { values in
          guard case .number(let input) = values["input"] else { throw UIError("Numeric input is required.") }
          return ["output": .number(input * 2)]
        }
    ])
  }
  public var body: some View {
    NavigationStack {
      OnDeviceGeneratedView(calculations: calculations, actions: ActionRegistry(async: [
        "submit": { event in
          // Host grants this single capability. Synthetic/local acknowledgement only.
          // event.state contains typed values; event.id supports host-side deduplication.
          return "Host received \(event.state.count) fields."
        }
      ]))
    }
  }
}
