import SwiftUI

/// Decode once, render real SwiftUI, and dispatch only to this host-owned registry.
@MainActor public struct SwiftUIIntelligenceView: View {
  private let document: UIDocument?
  private let error: String?
  private let actions: ActionRegistry
  private let embedded: Bool
  private let scrollTargetID: String?
  @State private var localState = DocumentState()
  private let suppliedState: DocumentState?
  @State private var actionPending = false
  @State private var result = "Ready. Tap an action to call the host."

  public init(data: Data, actions: ActionRegistry, embedded: Bool = false, scrollTargetID: String? = nil, state: DocumentState? = nil) {
    self.suppliedState = state
    self.actions = actions
    self.embedded = embedded
    self.scrollTargetID = scrollTargetID
    do {
      document = try UIDocument.decode(data, registeredActions: actions.names)
      error = nil
    } catch {
      document = nil
      self.error = error.localizedDescription
    }
  }

  public init(document: UIDocument, actions: ActionRegistry, embedded: Bool = false, scrollTargetID: String? = nil, state: DocumentState? = nil) {
    self.suppliedState = state
    self.actions = actions
    self.embedded = embedded
    self.scrollTargetID = scrollTargetID
    do {
      try document.validate(registeredActions: actions.names)
      self.document = document
      error = nil
    } catch {
      self.document = nil
      self.error = error.localizedDescription
    }
  }

  public var body: some View {
    VStack(spacing: 0) { renderedContent }
      
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("sdk-native-glass-document")
      .environment(suppliedState ?? localState)
      .environment(\.documentDestinations, destinations)
      .task(id: document.map { try? DocumentGenerationContract.canonicalJSON($0) }) {
        if let document { (suppliedState ?? localState).load(document) }
      }
  }

  @ViewBuilder private var renderedContent: some View {
    if let document {
      if embedded {
        GlassEffectContainer { NodeView(node: document.root, run: run) }
      } else {
        Group {
          ScrollViewReader { proxy in
            Group {
              if containsForm(document.root) {
                Form {
                  if document.root.type == .vstack {
                    ForEach(document.root.children.filter { destinations[$0.id] == nil }) {
                      NodeView(node: $0, run: run, showsSurface: false)
                    }
                  } else {
                    NodeView(node: document.root, run: run, showsSurface: false)
                  }
                }.accessibilityIdentifier("generic-document-scroll")
                  .scrollDismissesKeyboard(.interactively)
              } else {
                ScrollView {
                  GlassEffectContainer {
                    NodeView(node: document.root, run: run)
                      .frame(maxWidth: .infinity, alignment: .leading)
                      .padding()
                  }
                }.accessibilityIdentifier("generic-document-scroll")
              }
            }
              .task(id: scrollTargetID) {
                if let scrollTargetID { proxy.scrollTo(scrollTargetID, anchor: .top) }
              }
          }
        }
        .safeAreaInset(edge: .bottom, spacing: 12) {
          VStack(spacing: 12) {
            if containsAction(document.root) || !document.floatingActions.isEmpty {
              Text(result)
              .font(.callout)
              .multilineTextAlignment(.center)
              .padding(12)
              .frame(maxWidth: .infinity)
              
              .accessibilityIdentifier("action-result")
            }
            if !document.floatingActions.isEmpty {
              Group {
                HStack(spacing: 16) {
                  ForEach(document.floatingActions) { node in
                    Button {
                      run(node.action)
                    } label: {
                      SymbolText(text: node.title, icon: node.icon)
                    }
                    
                    .accessibilityIdentifier(node.id)
                  }
                }
              }
            }
          }
          .padding(.horizontal, 20)
          .padding(.bottom, 16)
        }
      }
    } else {
      ContentUnavailableView {
        Label("Cannot render UI", systemImage: "exclamationmark.triangle")
      } description: {
        Text(error ?? "Invalid UI JSON.")
      }
      
      .padding(20)
      .accessibilityIdentifier("ui-error")
    }
  }

  private var destinations: [String: UINode] {
    guard let document else { return [:] }
    var nodes: [UINode] = []; func visit(_ n: UINode) { nodes.append(n); n.children.forEach(visit) }; visit(document.root)
    let references = Set(nodes.filter { $0.type == .navigationLink }.map(\.destination))
    return Dictionary(uniqueKeysWithValues: nodes.filter { references.contains($0.id) }.map { ($0.id, $0) })
  }

  private func containsForm(_ node: UINode) -> Bool {
    node.type == .form || node.children.contains(where: containsForm)
  }

  private func containsAction(_ node: UINode) -> Bool {
    !node.action.isEmpty || node.children.contains(where: containsAction)
  }

  private func run(_ name: String) {
    guard !actionPending else { return }
    actionPending = true; result = "Working…"
    let event = ActionEvent(action: name, state: (suppliedState ?? localState).values)
    Task { @MainActor in
      defer { actionPending = false }
      do { result = try await actions.perform(event) } catch { result = "Action failed: \(error.localizedDescription)" }
    }
  }
}

enum DocumentSurfacePolicy {
  static func childSurface(parentShowsSurface: Bool) -> Bool {
    parentShowsSurface
  }
}

private struct NodeView: View {
  @Environment(DocumentState.self) private var state
  @Environment(\.documentDestinations) private var destinations
  let node: UINode
  let run: (String) -> Void
  var showsSurface = true
  var sectionTitle: String? = nil
  var inheritedCardColor: CardColor = .neutral
  private var effectiveCardColor: CardColor { showsSurface ? node.cardColor ?? inheritedCardColor : inheritedCardColor }

  // Type erasure is confined to recursion over a validated heterogeneous tree.
  @ViewBuilder var body: some View {
    if node.type == .form {
      Section {
        ForEach(node.children.filter { destinations[$0.id] == nil }) {
          NodeView(node: $0, run: run, showsSurface: false, sectionTitle: node.title)
        }
      } header: { SymbolText(text: node.title, icon: node.icon) }
    } else if node.type == .control {
      Group {
        if showsSurface { content.modifier(SwiftUIIntelligenceSurface(cardColor: effectiveCardColor)) } else { content }
      }.id(node.id)
    } else if node.type == .vstack || node.type == .hstack || node.type == .grid || node.type == .section || node.type == .form {
      surface.id(node.id).accessibilityElement(children: .contain).accessibilityIdentifier(node.id)
    } else {
      surface.id(node.id).accessibilityIdentifier(node.id)
    }
  }

  private var surface: some View {
    Group {
      if showsSurface && node.type != .button && node.type != .vstack && node.type != .hstack && node.type != .grid && node.type != .timeline && (!layoutHasSections || node.type == .section) && node.type != .navigationLink {
        content.frame(maxWidth: .infinity, maxHeight: node.type == .metric ? .infinity : nil, alignment: .topLeading)
          .modifier(SwiftUIIntelligenceSurface(inset: node.type == .metric ? 12 : 18, cardColor: effectiveCardColor))
      } else {
        content
      }
    }
  }

  private var content: AnyView {
    switch node.type {
    case .vstack:
      AnyView(
        VStack(alignment: .leading, spacing: max(8, node.spacing)) {
          ForEach(node.children.filter { destinations[$0.id] == nil }) { NodeView(node: $0, run: run, showsSurface: DocumentSurfacePolicy.childSurface(parentShowsSurface: showsSurface), sectionTitle: sectionTitle, inheritedCardColor: effectiveCardColor) }
        })
    case .hstack:
      AnyView(
        ViewThatFits(in: .horizontal) {
          HStack(spacing: node.spacing) {
            ForEach(node.children.filter { destinations[$0.id] == nil }) { NodeView(node: $0, run: run, showsSurface: DocumentSurfacePolicy.childSurface(parentShowsSurface: showsSurface), sectionTitle: sectionTitle, inheritedCardColor: effectiveCardColor) }
          }
          VStack(alignment: .leading, spacing: max(8, node.spacing)) {
            ForEach(node.children.filter { destinations[$0.id] == nil }) { NodeView(node: $0, run: run, showsSurface: DocumentSurfacePolicy.childSurface(parentShowsSurface: showsSurface), sectionTitle: sectionTitle, inheritedCardColor: effectiveCardColor) }
          }
        })
    case .grid:
      AnyView(
        AdaptiveNodeGrid(maxColumns: node.columnCount, spacing: node.spacing, minimumCellWidth: node.children.contains(where: { $0.type == .chart }) ? 240 : 90) {
          ForEach(node.children.filter { destinations[$0.id] == nil }) { NodeView(node: $0, run: run, showsSurface: showsSurface, sectionTitle: sectionTitle, inheritedCardColor: effectiveCardColor) }
        })
    case .text:
      AnyView(
        SymbolText(text: node.text, icon: node.icon).font(font).foregroundStyle(node.style == .caption ? .secondary : .primary))
    case .form:
      AnyView(Section {
        ForEach(node.children.filter { destinations[$0.id] == nil }) {
          NodeView(node: $0, run: run, showsSurface: false, sectionTitle: node.title)
        }
      } header: { SymbolText(text: node.title, icon: node.icon) })
    case .section:
      AnyView(
        VStack(alignment: .leading, spacing: max(8, node.spacing)) {
          if !node.children.contains(where: { $0.type == .text && $0.text == node.title }) {
            SymbolText(text: node.title, icon: node.icon).font(.headline).foregroundStyle(.primary)
          }
          ForEach(node.children.filter { destinations[$0.id] == nil }) { NodeView(node: $0, run: run, showsSurface: false, sectionTitle: node.title, inheritedCardColor: effectiveCardColor) }
        })
    case .list:
      AnyView(
        VStack(alignment: .leading, spacing: 10) {
          ForEach(Array(node.items.enumerated()), id: \.offset) { _, item in
            HStack(alignment: .top, spacing: 10) {
              Text("•").accessibilityHidden(true)
              Text(item).frame(maxWidth: .infinity, alignment: .leading)
            }
          }
        })
    case .table:
      AnyView(
        ViewThatFits(in: .horizontal) {
          Grid(alignment: .topLeading, horizontalSpacing: 18, verticalSpacing: 12) {
            GridRow {
              ForEach(Array(node.columns.enumerated()), id: \.offset) { _, column in
                Text(column).font(.subheadline.bold()).frame(
                  minWidth: 110, maxWidth: 200, alignment: .leading)
              }
            }
            ForEach(Array(node.rows.enumerated()), id: \.offset) { _, row in
              GridRow {
                ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                  Text(cell).frame(minWidth: 110, maxWidth: 200, alignment: .leading)
                }
              }
            }
          }.font(.subheadline).foregroundStyle(.primary)
          VStack(alignment: .leading, spacing: 16) {
            ForEach(Array(node.rows.enumerated()), id: \.offset) { _, row in
              VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(node.columns.enumerated()), id: \.offset) { index, column in
                  HStack(alignment: .top) {
                    Text(column).font(.subheadline.bold())
                    Spacer(minLength: 12)
                    Text(row[index]).font(.subheadline).multilineTextAlignment(.trailing)
                  }
                }
              }
              Divider()
            }
          }
        }.accessibilityElement(children: .contain))
    case .callout:
      AnyView(
        HStack(alignment: .top, spacing: 10) {
          Image(
            systemName: node.icon.map(SymbolCatalog.systemName(for:)) ?? (node.tone == .warning
              ? "exclamationmark.triangle"
              : node.tone == .success ? "checkmark.circle" : "info.circle")
          ).accessibilityLabel(node.tone.rawValue)
          Text(node.text).frame(maxWidth: .infinity, alignment: .leading)
        }.font(.callout).foregroundStyle(.primary))
    case .metric, .iconList, .badge, .progress, .chart:
      AnyView(PresentationNodeView(node: node, showsTitle: node.title != sectionTitle))
    case .control:
      AnyView(ControlNodeView(node: node))
    case .navigationLink:
      AnyView(NavigationLink {
        if let target = destinations[node.destination] {
          ScrollView {
            GlassEffectContainer { NodeView(node: target, run: run).padding(24) }
          }
            
            .environment(state).environment(\.documentDestinations, destinations)
            .navigationTitle(target.title)
        }
      } label: { Label(node.title, systemImage: "chevron.right") })
    case .timeline:
      AnyView(VStack(alignment: .leading, spacing: 20) {
        Text(node.title).font(.headline)
        ForEach(Array(node.events.enumerated()), id: \.offset) { _, event in
          VStack(alignment: .leading, spacing: 8) {
            Text(event.time).font(.subheadline.weight(.semibold))
            Group {
              if showsSurface {
                timelineRow(event).modifier(SwiftUIIntelligenceSurface(inset: 16, cardColor: event.cardColor ?? effectiveCardColor))
              } else {
                timelineRow(event)
              }
            }
          }
        }
      })
    case .button:
      AnyView(
        Button { run(node.action) } label: { SymbolText(text: node.title, icon: node.icon) }
          .accessibilityIdentifier(node.id))

    }
  }

  private func timelineRow(_ event: TimelineEvent) -> some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: "calendar").foregroundStyle((event.cardColor ?? effectiveCardColor).swiftUIColor).accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 6) {
        Text(event.title).font(.headline).fixedSize(horizontal: false, vertical: true)
        if !event.detail.isEmpty {
          Text(event.detail).font(.subheadline).foregroundStyle(.primary.opacity(0.85))
            .fixedSize(horizontal: false, vertical: true)
        }
      }.frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private var layoutHasSections: Bool {
    (node.type == .vstack || node.type == .hstack || node.type == .grid || node.type == .section) && node.children.contains { [.section, .metric, .chart, .progress, .iconList, .grid, .timeline].contains($0.type) || $0.children.contains { [.metric, .chart, .section].contains($0.type) } }
  }

  private var font: Font {
    switch node.style {
    case .title: .title2
    case .headline: .headline
    case .body: .body
    case .caption: .caption
    }
  }
}

/// Uses the proposed viewport width rather than a grid's unconstrained ideal width.
/// Column count remains a document choice; narrow screens reduce it without business rules.
private struct AdaptiveNodeGrid: Layout {
  let maxColumns: Int
  let spacing: Double
  let minimumCellWidth: CGFloat
  private func geometry(_ width: CGFloat, count: Int) -> (Int, CGFloat) {
    let columns = min(min(maxColumns, max(1, count)), max(1, Int((width + spacing) / (minimumCellWidth + spacing))))
    return (columns, max(0, (width - CGFloat(columns - 1) * spacing) / CGFloat(columns)))
  }
  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let fallbackWidth = CGFloat(maxColumns) * 120 + CGFloat(maxColumns - 1) * spacing
    let proposedWidth = proposal.width ?? fallbackWidth
    let width = proposedWidth.isFinite ? max(0, proposedWidth) : fallbackWidth
    let (columns, cellWidth) = geometry(width, count: subviews.count)
    var height: CGFloat = 0
    for start in stride(from: 0, to: subviews.count, by: columns) {
      let end = min(start + columns, subviews.count)
      let rowHeight = (start..<end).map { subviews[$0].sizeThatFits(.init(width: cellWidth, height: nil)).height }.max() ?? 0
      if start > 0 { height += spacing }
      height += rowHeight
    }
    return CGSize(width: width, height: height)
  }
  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    let (columns, cellWidth) = geometry(bounds.width, count: subviews.count)
    var y = bounds.minY
    for start in stride(from: 0, to: subviews.count, by: columns) {
      let end = min(start + columns, subviews.count)
      let rowHeight = (start..<end).map { subviews[$0].sizeThatFits(.init(width: cellWidth, height: nil)).height }.max() ?? 0
      for index in start..<end {
        subviews[index].place(at: CGPoint(x: bounds.minX + CGFloat(index - start) * (cellWidth + spacing), y: y), anchor: .topLeading, proposal: .init(width: cellWidth, height: rowHeight))
      }
      y += rowHeight + spacing
    }
  }
}

private struct DocumentDestinationsKey: EnvironmentKey {
  static let defaultValue: [String: UINode] = [:]
}
private extension EnvironmentValues {
  var documentDestinations: [String: UINode] {
    get { self[DocumentDestinationsKey.self] }
    set { self[DocumentDestinationsKey.self] = newValue }
  }
}

private struct ControlNodeView: View {
  @Environment(DocumentState.self) private var state
  let node: UINode
  private var text: Binding<String> {
    Binding(get: { if case .text(let v) = state.values[node.binding] { return v }; return "" },
            set: { state.edit(node.binding, .text($0)) })
  }
  private var number: Binding<Double> {
    Binding(get: { if case .number(let v) = state.values[node.binding] { return v }; return 0 },
            set: { state.edit(node.binding, .number($0)) })
  }
  private var boolean: Binding<Bool> {
    Binding(get: { if case .boolean(let v) = state.values[node.binding] { return v }; return false },
            set: { state.edit(node.binding, .boolean($0)) })
  }
  @ViewBuilder var body: some View {
    if let field = state.field(node.binding) {
      Group {
        switch node.controlType {
        case .textField: LabeledContent(node.title) { TextField("", text: text).accessibilityIdentifier(node.id) }
        case .textEditor:
          VStack(alignment: .leading) { Text(node.title); TextEditor(text: text).frame(minHeight: 100).accessibilityLabel(node.title).accessibilityIdentifier(node.id) }
        case .toggle: Toggle(node.title, isOn: boolean).accessibilityIdentifier(node.id)
        case .picker:
          LabeledContent(node.title) {
            Picker("", selection: text) { ForEach(field.options, id: \.self) { Text($0).tag($0) } }.labelsHidden().accessibilityIdentifier(node.id)
          }
        case .slider:
          VStack(alignment: .leading) {
            Text("\(node.title): \(number.wrappedValue.formatted())")
            Slider(value: number, in: field.minimum...field.maximum, step: field.step) { Text(node.title) }.accessibilityIdentifier(node.id)
          }
        case .stepper:
          Stepper("\(node.title): \(number.wrappedValue.formatted())", value: number, in: field.minimum...field.maximum, step: field.step).accessibilityIdentifier(node.id)
        case .datePicker:
          DatePicker(node.title, selection: Binding(get: {
            ISO8601DateFormatter().date(from: text.wrappedValue) ?? .distantPast
          }, set: { text.wrappedValue = ISO8601DateFormatter().string(from: $0) })).accessibilityIdentifier(node.id)
        }
      }
    }
  }
}
