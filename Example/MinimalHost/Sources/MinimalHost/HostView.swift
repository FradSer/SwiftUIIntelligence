import SwiftUIIntelligence
import SwiftUIIntelligenceFoundationModels
import SwiftUI

/// Builds as a separate package using only exported public APIs.
public struct HostView: View {
  public init() {}
  public var body: some View {
    NavigationStack {
      OnDeviceGeneratedView(actions: ActionRegistry(async: [
        "submit": { event in
          // Host grants this single capability. Synthetic/local acknowledgement only.
          // event.state contains typed values; event.id supports host-side deduplication.
          return "Host received \(event.state.count) fields."
        }
      ]))
    }
  }
}
