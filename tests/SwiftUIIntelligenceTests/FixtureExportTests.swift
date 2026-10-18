import Foundation
import Testing
import SwiftUIIntelligence
import SwiftUIIntelligenceExamples
import InteractionFixtureSupport

// Given no export directory, this test does not create files.
// Given an explicit directory, export the same validated acceptance fixtures.
@Test @MainActor func exportNativeInteractionFixturesWhenRequested() throws {
  guard let directory = ProcessInfo.processInfo.environment["SWIFTUIINTELLIGENCE_FIXTURE_EXPORT_DIR"],
    !directory.isEmpty else { return }

  let registry = try ExampleCalculations.registry()
  let equipment = try UIDocument.decode(
    JSONSerialization.data(withJSONObject: InteractionFixtures.equipment()),
    registeredActions: [], registeredCalculations: registry.names)
  let bill = try UIDocument.decode(
    JSONSerialization.data(withJSONObject: InteractionFixtures.bill()),
    registeredActions: [], registeredCalculations: registry.names)
  try EquipmentInteractionAcceptance.validate(equipment, registry: registry)
  try BillInteractionAcceptance.validate(bill, registry: registry)

  let fixtures = [("equipment.json", equipment), ("bill.json", bill)]
  let exports = try fixtures.map { name, document in
    let data = try DocumentGenerationContract.canonicalJSON(document)
    let decoded = try UIDocument.decode(data, registeredActions: [], registeredCalculations: registry.names)
    #expect(try DocumentGenerationContract.canonicalJSON(decoded) == data)
    return (name, data)
  }
  let folder = URL(fileURLWithPath: directory, isDirectory: true)
  try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  for (name, data) in exports {
    try data.write(to: folder.appendingPathComponent(name), options: .atomic)
  }
}
