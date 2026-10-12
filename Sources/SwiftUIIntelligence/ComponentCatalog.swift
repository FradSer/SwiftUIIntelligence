/// Exhaustive SDK capability inventory. Decoder enums and schema variants are checked
/// against this catalog; adding a kind also requires an exhaustive renderer switch.
public enum ComponentCatalog {
  public static let components = UINode.Kind.allCases
  public static let controls = UINode.ControlType.allCases
  public static let stateTypes = StateField.Kind.allCases
}
