import Foundation

/// Host-supplied semantic constraints apply equally to all providers and saved JSON.
public struct DocumentRequirements: Sendable {
  public let components: Set<UINode.Kind>
  public let stateCount: Int?
  public let controls: Set<UINode.ControlType>
  public let exactText: [String]
  public init(components: Set<UINode.Kind> = [], exactText: [String] = [], controls: Set<UINode.ControlType> = [], stateCount: Int? = nil) {
    self.stateCount = stateCount
    self.controls = controls; self.components = components; self.exactText = exactText
  }
  public func validate(_ document: UIDocument) throws {
    if let stateCount, document.state.count != stateCount { throw UIError("Declare exactly \(stateCount) state fields for the requested inputs; no title or decorative state.") }
    var nodes: [UINode] = []
    func visit(_ n: UINode) { nodes.append(n); n.children.forEach(visit) }
    visit(document.root); document.floatingActions.forEach(visit)
    if !controls.isEmpty && Set(nodes.filter { $0.type == .control }.map(\.controlType)) != controls { throw UIError("Use exactly these control types: \(controls.map(\.rawValue).sorted()).") }
    let missing = components.subtracting(nodes.map(\.type))
    guard missing.isEmpty else { throw UIError("Required components missing: \(missing.map(\.rawValue).sorted()).") }
    var strings: [String] = []
    for n in nodes {
      strings += [n.title, n.text, n.label, n.value, n.detail]
      strings += n.items; strings += n.columns
      for row in n.rows { strings += row }
      strings += n.iconItems.map(\.text)
      for event in n.events { strings += [event.time, event.title, event.detail] }
    }
    for field in document.state {
      if case .text(let v) = field.value { strings.append(v) }
      strings += field.options
    }
    for text in exactText where !strings.contains(text) {
      throw UIError("Required exact text missing: \(text)")
    }
  }
  var instructions: String {
    "\nRequired node kinds: \(components.map(\.rawValue).sorted()). Exact complete strings to preserve in a displayed field, event or state value: \(exactText)."
  }
}

extension UINode.ControlType {
  static let allNames = allCases.map(\.rawValue)
}
extension StateField.Kind {
  static let allNames = allCases.map(\.rawValue)
}
