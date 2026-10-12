import SwiftUI

/// Native regular Liquid Glass cards with system-relative concentric corners.
/// A 20pt minimum is this library's card fallback, not a universal Apple radius.
/// No added tint, rim, lining, border or shadow; controls retain native appearance.
public struct SwiftUIIntelligenceSurface: ViewModifier {
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @Environment(\.swiftUIIntelligenceTestReduceTransparency) private var testReduceTransparency
  private let shape = ConcentricRectangle(corners: .concentric(minimum: .fixed(20)))
  private let inset: CGFloat
  public init(inset: CGFloat = 18) { self.inset = max(0, inset) }
  public func body(content: Content) -> some View {
    Group {
      if reduceTransparency || testReduceTransparency {
        content.padding(inset).background(.background, in: shape)
      } else {
        content.padding(inset).glassEffect(in: shape)
      }
    }
  }
}

/// Neutral system background shared by standalone, embedded and example views.
/// Retains the public entry point without imposing a proprietary visual theme.
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
  /// SwiftUIIntelligence-owned test preview only; production reads the public system value.
  @_spi(Testing) public var swiftUIIntelligenceTestReduceTransparency: Bool {
    get { self[GlassTestReduceTransparencyKey.self] }
    set { self[GlassTestReduceTransparencyKey.self] = newValue }
  }
}
