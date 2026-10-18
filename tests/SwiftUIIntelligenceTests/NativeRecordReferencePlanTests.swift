import Foundation
import SwiftUIIntelligence
@testable import SwiftUIIntelligenceFoundationModels
import Testing

@Suite struct NativeRecordReferencePlanTests {
  private func signature(_ id: String = "equipment") -> CalculationRegistry.Signature {
    .init(id: id, inputs: [:], outputs: [:], recordInputs: [
      "products": .init(fields: ["name": .text]),
      "measurements": .init(fields: ["product": .text, "value": .number, "active": .boolean]),
      "conditions": .init(fields: ["product": .text]),
    ], recordReferences: [.init(input: "measurements", field: "product", targetInput: "products")])
  }

  private func collection(_ id: String = "authored", fields: [String: String] = ["name": "text"],
    rows: [[String: Any]] = [["id": "p-2", "values": ["name": "Display name"]], ["id": "p-1", "values": ["name": "Other"]]]) throws -> Data {
    try JSONSerialization.data(withJSONObject: ["id": id, "schema": ["fields": fields], "rows": rows], options: [.prettyPrinted, .sortedKeys])
  }

  @Test func duplicateRowsReportTheAuthoredIDAndInputWithoutRepair() throws {
    let step = try NativeRecordReferencePlan.steps(signatures: [signature()])[1]
    let duplicated = try collection(rows: [["id": "same-row", "values": ["name": "One"]], ["id": "same-row", "values": ["name": "Two"]]])
    do {
      _ = try NativeRecordReferencePlan.normalizeCollection(duplicated, step: step, accepted: [:])
      Issue.record("Duplicate row IDs must reject.")
    } catch {
      #expect(error.localizedDescription.contains("same-row"))
      #expect(error.localizedDescription.contains("products"))
    }
  }

  @Test func nativeRecordTextLimitMatchesSchemaCodePoints() throws {
    let step = try NativeRecordReferencePlan.steps(signatures: [signature()])[1]
    for count in [500, 501] {
      let text = String(repeating: "e\u{301}", count: count)
      let data = try collection(rows: [["id": "row", "values": ["name": text]]])
      if count == 500 {
        #expect(try NativeRecordReferencePlan.normalizeCollection(data, step: step, accepted: [:]).originalData == data)
      } else {
        #expect(throws: UIError.self) { try NativeRecordReferencePlan.normalizeCollection(data, step: step, accepted: [:]) }
      }
    }
  }

  @Test func referenceCatalogContainsOnlyDeclaredDependencies() throws {
    let step = try NativeRecordReferencePlan.steps(signatures: [signature()])[2]
    let target = try JSONDecoder().decode(RecordCollection.self, from: collection())
    let catalog = try NativeRecordReferencePlan.targetCatalog(for: step, accepted: ["equipment": ["products": target, "conditions": target]])
    let decoded = try #require(JSONSerialization.jsonObject(with: catalog) as? [String: Any])
    #expect(Set(decoded.keys) == ["products"])
    let independent = try NativeRecordReferencePlan.steps(signatures: [signature()])[0]
    let empty = try NativeRecordReferencePlan.targetCatalog(for: independent, accepted: ["equipment": ["products": target]])
    #expect((try JSONSerialization.jsonObject(with: empty) as? [String: Any])?.isEmpty == true)
  }

  @Test func targetsPrecedeSourcesAndIndependentInputsStaySortedWithinCapability() throws {
    // Given reversed capabilities, planning keeps namespaces and uses metadata, not field names.
    let steps = try NativeRecordReferencePlan.steps(signatures: [signature("z"), signature("a")])
    #expect(steps.map { "\($0.capabilityID).\($0.input)" } == [
      "a.conditions", "a.products", "a.measurements", "z.conditions", "z.products", "z.measurements",
    ])
    #expect(steps[0].references.isEmpty)
    #expect(steps[2].references.first?.targetInput == "products")
    #expect(try NativeRecordReferencePlan.steps(signatures: []).isEmpty)
  }

  @Test func twoTargetsPrecedeAssignmentsAndBothReferencesAreRequired() throws {
    let signature = CalculationRegistry.Signature(id: "bill", inputs: [:], outputs: [:], recordInputs: [
      "assignments": .init(fields: ["item": .text, "person": .text]),
      "items": .init(fields: ["name": .text]), "people": .init(fields: ["name": .text]),
    ], recordReferences: [.init(input: "assignments", field: "person", targetInput: "people"),
      .init(input: "assignments", field: "item", targetInput: "items")])
    let steps = try NativeRecordReferencePlan.steps(signatures: [signature])
    #expect(steps.map(\.input) == ["items", "people", "assignments"])
    let target = try JSONDecoder().decode(RecordCollection.self, from: collection())
    let accepted = ["bill": ["items": target, "people": target]]
    let data = try collection(fields: ["item": "text", "person": "text"], rows: [["id": "a", "values": ["item": "p-1", "person": "p-2"]]])
    #expect(try NativeRecordReferencePlan.normalizeCollection(data, step: steps[2], accepted: accepted).originalData == data)
    for field in ["item", "person"] {
      var values = ["item": "p-1", "person": "p-2"]; values[field] = "Display name"
      #expect(throws: (any Error).self) {
        try NativeRecordReferencePlan.normalizeCollection(collection(fields: ["item": "text", "person": "text"], rows: [["id": "a", "values": values]]), step: steps[2], accepted: accepted)
      }
    }
  }

  @Test func schemaUsesActualAcceptedIDsAndNormalizationPreservesBytes() throws {
    let steps = try NativeRecordReferencePlan.steps(signatures: [signature()])
    let target = try NativeRecordReferencePlan.normalizeCollection(collection(), step: steps[1], accepted: [:])
    let accepted = ["equipment": ["products": target.collection]]
    let schema = try JSONSerialization.jsonObject(with: NativeRecordReferencePlan.schemaForStep(steps[2], accepted: accepted)) as! [String: Any]
    let properties = schema["properties"] as! [String: [String: Any]]
    let rows = properties["rows"]!
    let item = rows["items"] as! [String: Any]
    let itemProperties = item["properties"] as! [String: [String: Any]]
    let values = itemProperties["values"]!["properties"] as! [String: [String: Any]]
    #expect(schema["additionalProperties"] as? Bool == false)
    #expect(rows["maxItems"] as? Int == 32)
    #expect(values["product"]?["enum"] as? [String] == ["p-1", "p-2"])
    #expect(values["value"]?["type"] as? String == "number")
    #expect((properties["id"]?["description"] as? String)?.contains(steps[2].input) == true)
    #expect((itemProperties["id"]?["description"] as? String)?.contains("row") == true)
    let data = try collection(fields: ["product": "text", "value": "number", "active": "boolean"], rows: [["id": "m", "values": ["product": "p-1", "value": 1.25, "active": true]]])
    let normalized = try NativeRecordReferencePlan.normalizeCollection(data, step: steps[2], accepted: accepted)
    #expect(normalized.originalData == data)
    #expect(normalized.collection.id == "authored")
    #expect(normalized.collection.rows[0].values["value"] == .number(1.25))
    #expect(throws: (any Error).self) { try NativeRecordReferencePlan.schemaForStep(steps[2], accepted: ["other": ["products": target.collection]]) }
  }

  @Test func joinRelationCollectionRestrictsMaxItemsToCartesianProduct() throws {
    let signature = CalculationRegistry.Signature(
      id: "split", inputs: [:], outputs: [:],
      recordInputs: [
        "items": .init(fields: ["name": .text]),
        "people": .init(fields: ["name": .text]),
        "assignments": .init(fields: ["included": .boolean, "itemID": .text, "personID": .text])
      ],
      recordReferences: [
        .init(input: "assignments", field: "itemID", targetInput: "items"),
        .init(input: "assignments", field: "personID", targetInput: "people")
      ]
    )
    let steps = try NativeRecordReferencePlan.steps(signatures: [signature])
    let items = try JSONDecoder().decode(RecordCollection.self, from: collection(fields: ["name": "text"], rows: [["id": "i1", "values": ["name": "Soup"]], ["id": "i2", "values": ["name": "Tea"]]]))
    let people = try JSONDecoder().decode(RecordCollection.self, from: collection(fields: ["name": "text"], rows: [["id": "p1", "values": ["name": "Ada"]], ["id": "p2", "values": ["name": "Bo"]], ["id": "p3", "values": ["name": "Cy"]]]))
    let accepted = ["split": ["items": items, "people": people]]
    let assignmentStep = try #require(steps.first(where: { $0.input == "assignments" }))
    let data = try NativeRecordReferencePlan.schemaForStep(assignmentStep, accepted: accepted)
    let schema = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    let properties = schema["properties"] as! [String: [String: Any]]
    let rowsObj = try #require(properties["rows"] as? [String: Any])
    #expect(rowsObj["maxItems"] as? Int == 6)
  }

  @Test func emptyTargetForcesEmptyRowsWithoutAnEmptyEnumAndStillRequiresTarget() throws {
    let steps = try NativeRecordReferencePlan.steps(signatures: [signature()])
    let empty = try JSONDecoder().decode(RecordCollection.self, from: collection(rows: []))
    let accepted = ["equipment": ["products": empty]]
    let data = try NativeRecordReferencePlan.schemaForStep(steps[2], accepted: accepted)
    let schema = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    let properties = schema["properties"] as! [String: [String: Any]]
    #expect(properties["rows"]?["maxItems"] as? Int == 0)
    #expect(!String(decoding: data, as: UTF8.self).contains("\"enum\":[]"))
    let fields = ["product": "text", "value": "number", "active": "boolean"]
    _ = try NativeRecordReferencePlan.normalizeCollection(collection(fields: fields, rows: []), step: steps[2], accepted: accepted)
    #expect(throws: (any Error).self) { try NativeRecordReferencePlan.normalizeCollection(collection(fields: fields, rows: []), step: steps[2], accepted: [:]) }
    #expect(throws: (any Error).self) { try NativeRecordReferencePlan.normalizeCollection(collection(fields: fields, rows: [["id": "m", "values": ["product": "p-1", "value": 1, "active": true]]]), step: steps[2], accepted: accepted) }
  }

  @Test func invalidMetadataAndBoundedCollectionViolationsRejectWithoutRepair() throws {
    let schemas: [String: RecordSchema] = ["a": .init(fields: ["ref": .text]), "b": .init(fields: ["ref": .text])]
    for references: [RecordInputReference] in [
      [.init(input: "a", field: "ref", targetInput: "missing")],
      [.init(input: "a", field: "missing", targetInput: "b")],
      [.init(input: "a", field: "ref", targetInput: "b"), .init(input: "b", field: "ref", targetInput: "a")],
      [.init(input: "a", field: "ref", targetInput: "b"), .init(input: "a", field: "ref", targetInput: "b")],
    ] {
      #expect(throws: (any Error).self) { try NativeRecordReferencePlan.steps(signatures: [.init(id: "bad", inputs: [:], outputs: [:], recordInputs: schemas, recordReferences: references)]) }
    }
    #expect(throws: (any Error).self) { try NativeRecordReferencePlan.steps(signatures: [.init(id: "bad", inputs: [:], outputs: [:], recordInputs: ["a": .init(fields: ["time": .instant])])]) }
    #expect(throws: (any Error).self) { try NativeRecordReferencePlan.steps(signatures: [signature(), signature()]) }
    let step = try NativeRecordReferencePlan.steps(signatures: [signature()])[1]
    let invalid = [
      try collection("bad id"), try collection(fields: ["other": "text"]),
      try collection(rows: [["id": "p", "values": ["name": 1]]]),
      try collection(rows: [["id": "p", "values": ["name": "ok", "extra": true]]]),
      try collection(rows: Array(repeating: ["id": "p", "values": ["name": "ok"]], count: 2)),
      try collection(rows: (0..<33).map { ["id": "p\($0)", "values": ["name": "ok"]] }),
      Data(#"{"id":"a","schema":{"fields":{"name":"text"}},"rows":[],"extra":1}"#.utf8),
      Data(#"{"id":"a","schema":{"fields":{"name":"text"}}}"#.utf8),
      Data(repeating: 32, count: 65_537),
    ]
    for data in invalid {
      #expect(throws: (any Error).self) { try NativeRecordReferencePlan.normalizeCollection(data, step: step, accepted: [:]) }
    }
  }
}
