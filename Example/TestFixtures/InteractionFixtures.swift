// Synthetic acceptance fixtures only. These are not page-generation templates.
public enum InteractionFixtures {
  public static func equipment(prefix: String = "mapped", chartFields: [String] = ["name", "value", "field"]) -> [String: Any] {
    func collection(_ id: String, fields: [String: String], rows: [[String: Any]]) -> [String: Any] {
      ["id": id, "schema": ["fields": fields], "rows": rows]
    }
    func table(_ id: String, source: String, fields: [String], editable: [String] = []) -> [String: Any] {
      ["id": id, "type": "table", "columns": fields, "rows": [fields], "recordSource": source,
        "recordFields": fields, "editableFields": editable]
    }
    let products = "\(prefix)-products", measurements = "\(prefix)-measurements", conditions = "\(prefix)-conditions"
    let matches = "\(prefix)-matches", points = "\(prefix)-points"
    let ids = ["\(prefix)-tree", "\(prefix)-ground"]
    let names = ["Cedar", "Moss"]
    let rows = ids.enumerated().flatMap { index, id in
      ["price", "weight"].enumerated().map { fieldIndex, field -> [String: Any] in
        ["id": "\(prefix)-measure-\(index)-\(fieldIndex)", "values": ["productID": id, "field": field,
          "value": [[120, 900], [85, 1200]][index][fieldIndex]]]
      }
    }
    return ["version": 1, "records": [
      collection(products, fields: ["name": "text", "selected": "boolean"], rows: ids.enumerated().map {
        ["id": $0.element, "values": ["name": names[$0.offset], "selected": $0.offset == 0]]
      }),
      collection(measurements, fields: ["productID": "text", "field": "text", "value": "number"], rows: rows),
      collection(conditions, fields: ["field": "text", "minimum": "number", "maximum": "number"], rows: [
        ["id": "\(prefix)-money", "values": ["field": "price", "minimum": 0, "maximum": 130]],
        ["id": "\(prefix)-mass", "values": ["field": "weight", "minimum": 0, "maximum": 1300]],
      ]),
    ], "calculations": [["id": "\(prefix)-comparison", "capability": "compare-records", "inputs": [:], "outputs": [:],
      "recordInputs": ["products": products, "measurements": measurements, "conditions": conditions],
      "recordOutputs": ["matches": matches, "measurements": points]]],
      "root": ["id": "generic", "type": "vstack", "children": [
        table("selector", source: products, fields: ["name", "selected"], editable: ["selected"]),
        table("bounds", source: conditions, fields: ["field", "minimum", "maximum"], editable: ["minimum", "maximum"]),
        table("matches", source: matches, fields: ["name", "selected"]),
        table("values", source: points, fields: ["name", "field", "value"]),
        ["id": "plot", "type": "chart", "title": "Price (USD) and weight (g)", "chartStyle": "bar",
          "points": [["label": "Pending", "value": 1, "series": "Pending"]], "recordSource": points, "recordFields": chartFields],
      ]],
    ]
  }

  public static func bill(prefix: String = "mapped", control: String = "stepper") -> [String: Any] {
    let people = ["Ada", "Bo", "Cy"]
    // Reverse lexical order in one fixture so remainder recipients are not fixed by names.
    let ids = prefix == "zulu" ? ["z-person", "m-person", "a-person"] : people.indices.map { "\(prefix)-person-\($0)" }
    let itemIDs = ["\(prefix)-soup", "\(prefix)-tea"]
    func collection(_ id: String, fields: [String: String], rows: [[String: Any]]) -> [String: Any] {
      ["id": id, "schema": ["fields": fields], "rows": rows]
    }
    func table(_ id: String, source: String, fields: [String], editable: [String] = []) -> [String: Any] {
      ["id": id, "type": "table", "columns": fields, "rows": [fields], "recordSource": source,
        "recordFields": fields, "editableFields": editable]
    }
    let assignments = itemIDs.enumerated().flatMap { itemIndex, item in
      ids.enumerated().map { personIndex, person -> [String: Any] in
        ["id": "\(prefix)-pair-\(itemIndex)-\(personIndex)", "values": ["itemID": item, "personID": person,
          "included": itemIndex == 0 ? personIndex != 2 : personIndex != 0]]
      }
    }
    return ["version": 1,
      "state": [
        ["id": "service", "kind": "number", "value": 151, "minimum": 0, "maximum": 10000, "step": 1],
        ["id": "payable", "kind": "number", "value": 0, "minimum": 0, "maximum": 1000000000],
        ["id": "unrelated", "kind": "number", "value": 151, "minimum": 0, "maximum": 10000],
      ],
      "records": [
        collection("source-people", fields: ["name": "text"], rows: zip(ids, people).map { ["id": $0.0, "values": ["name": $0.1]] }),
        collection("source-items", fields: ["name": "text", "amountMinor": "number"], rows: [
          ["id": itemIDs[0], "values": ["name": "Soup", "amountMinor": 1001]],
          ["id": itemIDs[1], "values": ["name": "Tea", "amountMinor": 502]],
        ]),
        collection("source-matrix", fields: ["itemID": "text", "personID": "text", "included": "boolean"], rows: assignments),
      ],
      "calculations": [["id": "authored-split", "capability": "split-bill", "inputs": ["feeMinor": "service"],
        "outputs": ["payableMinor": "payable"], "recordInputs": ["people": "source-people", "items": "source-items", "assignments": "source-matrix"],
        "recordOutputs": ["breakdown": "derived-people", "shares": "derived-shares"]]],
      "root": ["id": "generic-stack", "type": "vstack", "children": [
        table("items-editor", source: "source-items", fields: ["name", "amountMinor"], editable: ["amountMinor"]),
        table("matrix-editor", source: "source-matrix", fields: ["itemID", "personID", "included"], editable: ["included"]),
        ["id": "fee-editor", "type": "control", "title": "Service fee", "controlType": control, "binding": "service"],
        table("people-output", source: "derived-people", fields: ["name", "foodMinor", "feeMinor", "totalMinor"]),
        table("shares-output", source: "derived-shares", fields: ["name", "item", "amountMinor"]),
        ["id": "payable-output", "type": "metric", "label": "Payable (MINOR UNITS)", "detail": "Exact integer amount", "value": "0", "valueBinding": "payable", "icon": "people"],
      ]],
    ]
  }
}
