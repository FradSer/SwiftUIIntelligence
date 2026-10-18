import Foundation

public struct RecordCollection: Codable, Sendable {
  public let id: String
  public let schema: RecordSchema
  public let rows: [RecordRow]

  private enum CodingKeys: String, CodingKey { case id, schema, rows }
  public init(from decoder: any Decoder) throws {
    try checkKeys(decoder, allowed: ["id", "schema", "rows"])
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    schema = try container.decode(RecordSchema.self, forKey: .schema)
    rows = try container.decode([RecordRow].self, forKey: .rows)
  }
}

extension UIDocument {
  func validateRecords() throws {
    guard records.count <= 16, Set(records.map(\.id)).count == records.count else {
      throw UIError("A document permits at most 16 unique record collections.")
    }
    for collection in records {
      guard validIdentifier(collection.id) else { throw UIError("Invalid record collection ID.") }
      try collection.schema.validate(collection.rows)
    }
  }
}
