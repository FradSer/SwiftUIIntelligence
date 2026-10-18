import Foundation

/// Host limits for one numeric calculation input. Step describes a control, not a value lattice.
public struct InputNumberConstraint: Codable, Sendable, Equatable {
  public let minimum: Double
  public let maximum: Double
  public let integer: Bool
  public let step: Double?

  public init(minimum: Double, maximum: Double, integer: Bool = false, step: Double? = nil) {
    self.minimum = minimum
    self.maximum = maximum
    self.integer = integer
    self.step = step
  }

  private enum CodingKeys: String, CodingKey { case minimum, maximum, integer, step }

  public init(from decoder: any Decoder) throws {
    try checkKeys(decoder, allowed: ["minimum", "maximum", "integer", "step"])
    let container = try decoder.container(keyedBy: CodingKeys.self)
    minimum = try container.decode(Double.self, forKey: .minimum)
    maximum = try container.decode(Double.self, forKey: .maximum)
    integer = container.contains(.integer) ? try container.decode(Bool.self, forKey: .integer) : false
    step = container.contains(.step) ? try container.decode(Double.self, forKey: .step) : nil
  }

  /// Checks the host metadata without constructing a state declaration.
  public func validate() throws {
    guard minimum.isFinite, maximum.isFinite, abs(minimum) <= 1e9, abs(maximum) <= 1e9, minimum <= maximum,
      !integer || (minimum.rounded() == minimum && maximum.rounded() == maximum) else {
      throw UIError("Invalid numeric input constraint bounds.")
    }
    if let step {
      guard step.isFinite, step > 0, step <= 1e9, !integer || step.rounded() == step else {
        throw UIError("Invalid numeric input constraint step.")
      }
    }
  }

  func validate(_ value: StateValue) throws {
    guard case .number(let number) = value, number.isFinite, number >= minimum, number <= maximum,
      !integer || number.rounded() == number else {
      throw UIError("Calculation input violates its numeric constraint.")
    }
  }

  /// Checks a bound field declaration and its initial value against these host limits.
  /// Call this method before a native adapter accepts generated input metadata.
  public func validate(field: StateField) throws {
    try validate()
    guard field.kind == .number, field.minimum.isFinite, field.maximum.isFinite,
      field.minimum >= minimum, field.maximum <= maximum, field.minimum <= field.maximum,
      field.step.isFinite, field.step > 0, field.step <= 1e9,
      !integer || (field.minimum.rounded() == field.minimum && field.maximum.rounded() == field.maximum
        && field.step.rounded() == field.step),
      step == nil || step == field.step else {
      throw UIError("Numeric input declaration violates its host constraint.")
    }
    try validate(field.value)
    try field.validate(field.value)
  }
}
