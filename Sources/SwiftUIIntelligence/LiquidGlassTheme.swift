import SwiftUI

/// Regular Liquid Glass cards use concentric corners without added shadows.
public struct SwiftUIIntelligenceSurface: ViewModifier {
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @Environment(\.swiftUIIntelligenceTestReduceTransparency) private var testReduceTransparency
  private let shape = ConcentricRectangle(corners: .concentric(minimum: .fixed(20)))
  private let inset: CGFloat
  private let cardColor: CardColor
  public init(inset: CGFloat = 18, cardColor: CardColor = .neutral) {
    self.inset = max(0, inset)
    self.cardColor = cardColor
  }
  public func body(content: Content) -> some View {
    Group {
      if reduceTransparency || testReduceTransparency {
        content.padding(inset).background {
            shape.fill(.background)
              .overlay {
                if cardColor != .neutral { shape.fill(cardColor.swiftUIColor.opacity(0.12)) }
              }
          }
      } else {
        content.padding(inset).glassEffect(cardColor == .neutral ? .regular : .regular.tint(cardColor.swiftUIColor.opacity(0.22)), in: shape)
      }
    }
  }
}

/// Neutral system background shared by standalone, embedded and example views.
public struct SwiftUIIntelligenceBackdrop: View {
  public init() {}
  public var body: some View {
    Rectangle().fill(.background).accessibilityHidden(true)
  }
}

private struct GlassTestReduceTransparencyKey: EnvironmentKey {
  static let defaultValue = false
}
extension EnvironmentValues {
  /// Test override for the system Reduce Transparency fallback.
  @_spi(Testing) public var swiftUIIntelligenceTestReduceTransparency: Bool {
    get { self[GlassTestReduceTransparencyKey.self] }
    set { self[GlassTestReduceTransparencyKey.self] = newValue }
  }
}

extension CardColor {
  var swiftUIColor: Color {
    switch self {
    case .neutral: .primary
    case .blue: .blue
    case .orange: .orange
    case .green: .green
    case .purple: .purple
    }
  }
}
