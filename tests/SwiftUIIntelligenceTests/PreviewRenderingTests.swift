import Foundation
import SwiftUI
import SwiftUIIntelligence
import Testing

@Test @MainActor func previewRendererPublicAPI() throws {
  // Given a validated component, when a client creates a preview without actions or
  // accepted state, then both public initializer forms compile as SwiftUI views.
  // This test does not establish native interaction or scrolling behavior.
  let document = try UIDocument.decode(
    Data(#"{"version":1,"root":{"id":"preview","type":"text","text":"Draft"}}"#.utf8),
    registeredActions: [])
  func requireView<V: View>(_ view: V) {}
  requireView(DocumentPreviewView(document: document))
  requireView(DocumentPreviewView(document: document, calculations: nil))
}
