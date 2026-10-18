import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct GeneratedOriginalPassages: View {
  let sources: [String]

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      ForEach(Array(sources.enumerated()), id: \.offset) { index, source in
        VStack(alignment: .leading, spacing: 8) {
          Text("Passage \(index + 1)").font(.subheadline).foregroundStyle(.secondary)
          Text(verbatim: source)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("generated-source-text-\(index)")
        }
      }
    }.frame(maxWidth: .infinity, alignment: .leading)
  }
}

enum GeneratedDocumentPanel: String, Identifiable {
  case original, details
  var id: String { rawValue }
}

/// Read-only inspection of host provenance, exact source passages, and accepted JSON.
struct GeneratedDocumentPanels: View {
  @Environment(\.dismiss) private var dismiss
  let panel: GeneratedDocumentPanel
  let sources: [String]
  let providerLabel: String
  let revision: Int
  let documentJSON: Data?

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Text(panel == .original ? "Original" : "Details").font(.headline)
        Spacer()
        Button("Done") { dismiss() }
          .accessibilityIdentifier("generated-panel-done")
      }
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          switch panel {
          case .original:
            GeneratedOriginalPassages(sources: sources)
          case .details:
            VStack(alignment: .leading, spacing: 8) {
              Text("Provider").font(.subheadline).foregroundStyle(.secondary)
              Text(verbatim: providerLabel)
                .textSelection(.enabled)
                .accessibilityIdentifier("generated-details-provider")
              Text("Revision \(revision)")
                .accessibilityIdentifier("generated-details-revision")
            }
            if let documentJSON {
              let json = String(decoding: documentJSON, as: UTF8.self)
              HStack {
                Text("Document JSON").font(.headline)
                Spacer()
                #if canImport(UIKit) || canImport(AppKit)
                Button("Copy JSON") { copyJSON(json) }
                  .accessibilityIdentifier("generated-copy-json")
                #endif
                ShareLink(item: json) { Label("Share JSON", systemImage: "square.and.arrow.up") }
                  .accessibilityIdentifier("generated-share-json")
              }
              Text(verbatim: json)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("generated-details-json")
            }
          }
        }.frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .padding()
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier(panel == .original ? "generated-original-panel" : "generated-details-panel")
  }

  #if canImport(UIKit) || canImport(AppKit)
  private func copyJSON(_ json: String) {
    #if canImport(UIKit)
    UIPasteboard.general.string = json
    #elseif canImport(AppKit)
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(json, forType: .string)
    #endif
  }
  #endif
}
