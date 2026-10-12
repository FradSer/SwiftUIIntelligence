import SwiftUIIntelligence
import SwiftUI

@MainActor public struct WeatherDemoView: View {
  private let document: WeatherDocument?
  private let error: String?
  public init(data: Data, actions: ActionRegistry) {
    do {
      document = try WeatherDocument.decode(data, registeredActions: actions.names)
      error = nil
    } catch {
      document = nil
      self.error = error.localizedDescription
    }
  }
  public var body: some View {
    VStack(spacing: 0) { content }
      
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("sdk-native-glass-weather")
  }
  @ViewBuilder private var content: some View {
    if let document {
      WeatherDashboardView(weather: document.root.weather, stage: document.root.stage.rawValue)
    } else {
      ContentUnavailableView {
        Label("Cannot render UI", systemImage: "exclamationmark.triangle")
      } description: {
        Text(error ?? "Invalid weather JSON.")
      }
      
      .padding(20)
      .accessibilityIdentifier("ui-error")
    }
  }
}
