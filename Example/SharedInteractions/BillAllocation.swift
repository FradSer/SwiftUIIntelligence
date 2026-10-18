// Example-owned calculation shared by runnable hosts and regression tests.
public enum BillAllocation {
  /// All amounts use the minor unit of one currency selected by the caller.
  public struct Input: Equatable, Sendable {
    public let personIDs: [String]
    public let items: [Item]
    public let fee: Int64

    public init(personIDs: [String], items: [Item], fee: Int64) {
      self.personIDs = personIDs
      self.items = items
      self.fee = fee
    }
  }

  public struct Item: Equatable, Sendable {
    public let id: String
    public let amount: Int64
    public let participantIDs: [String]

    public init(id: String, amount: Int64, participantIDs: [String]) {
      self.id = id
      self.amount = amount
      self.participantIDs = participantIDs
    }
  }

  public struct ItemShare: Equatable, Sendable {
    public let itemID: String
    public let amount: Int64

    public init(itemID: String, amount: Int64) {
      self.itemID = itemID
      self.amount = amount
    }
  }

  public struct Person: Equatable, Sendable {
    public let id: String
    public let itemShares: [ItemShare]
    public let food: Int64
    public let fee: Int64
    public let total: Int64

    public init(id: String, itemShares: [ItemShare], food: Int64, fee: Int64, total: Int64) {
      self.id = id
      self.itemShares = itemShares
      self.food = food
      self.fee = fee
      self.total = total
    }
  }

  public struct Result: Equatable, Sendable {
    public let people: [Person]
    public let payable: Int64

    public init(people: [Person], payable: Int64) {
      self.people = people
      self.payable = payable
    }
  }

  public enum AllocationError: Error, Equatable, Sendable {
    case duplicatePersonID(String)
    case duplicateItemID(String)
    case negativeItemAmount(String)
    case negativeFee
    case missingParticipants(String)
    case unknownParticipant(itemID: String, personID: String)
    case duplicateParticipant(itemID: String, personID: String)
    case feeWithoutFood
    case overflow
  }

  /// Returns a complete bill, ordered by person ID and item ID, or throws.
  public static func allocate(_ input: Input) throws -> Result {
    guard input.fee >= 0 else { throw AllocationError.negativeFee }
    var knownPeople = Set<String>()
    for id in input.personIDs {
      guard knownPeople.insert(id).inserted else { throw AllocationError.duplicatePersonID(id) }
    }
    var knownItems = Set<String>()
    var foodTotal: Int64 = 0
    for item in input.items {
      guard knownItems.insert(item.id).inserted else { throw AllocationError.duplicateItemID(item.id) }
      guard item.amount >= 0 else { throw AllocationError.negativeItemAmount(item.id) }
      guard item.amount == 0 || !item.participantIDs.isEmpty else {
        throw AllocationError.missingParticipants(item.id)
      }
      var participants = Set<String>()
      for id in item.participantIDs {
        guard knownPeople.contains(id) else {
          throw AllocationError.unknownParticipant(itemID: item.id, personID: id)
        }
        guard participants.insert(id).inserted else {
          throw AllocationError.duplicateParticipant(itemID: item.id, personID: id)
        }
      }
      foodTotal = try add(foodTotal, item.amount)
    }
    guard foodTotal > 0 || input.fee == 0 else { throw AllocationError.feeWithoutFood }
    let payable = try add(foodTotal, input.fee)
    let ids = input.personIDs.sorted()
    let indices = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($0.element, $0.offset) })
    var shares = Array(repeating: [ItemShare](), count: ids.count)
    var food = Array(repeating: Int64(0), count: ids.count)
    for item in input.items.sorted(by: { $0.id < $1.id }) where !item.participantIDs.isEmpty {
      let participants = item.participantIDs.sorted()
      let count = Int64(participants.count)
      let base = item.amount / count
      let remainder = item.amount % count
      for (rank, id) in participants.enumerated() {
        let amount = try add(base, Int64(rank) < remainder ? 1 : 0)
        // Validation above guarantees that each participant has an index.
        let index = indices[id]!
        shares[index].append(.init(itemID: item.id, amount: amount))
        food[index] = try add(food[index], amount)
      }
    }
    var fees = Array(repeating: Int64(0), count: ids.count)
    if foodTotal > 0 {
      var remainders = Array(repeating: UInt64(0), count: ids.count)
      var allocated: Int64 = 0
      for index in ids.indices {
        // A 128-bit product avoids rejecting a valid bill when fee * food exceeds Int64.
        let product = UInt64(input.fee).multipliedFullWidth(by: UInt64(food[index]))
        let division = UInt64(foodTotal).dividingFullWidth(product)
        fees[index] = Int64(division.quotient)
        remainders[index] = division.remainder
        allocated = try add(allocated, fees[index])
      }
      let ranked = ids.indices.sorted {
        remainders[$0] == remainders[$1] ? ids[$0] < ids[$1] : remainders[$0] > remainders[$1]
      }
      let residual = input.fee - allocated
      for index in ranked.prefix(Int(residual)) {
        fees[index] = try add(fees[index], 1)
      }
    }
    let people = try ids.indices.map { index in
      Person(id: ids[index], itemShares: shares[index], food: food[index], fee: fees[index],
        total: try add(food[index], fees[index]))
    }
    return Result(people: people, payable: payable)
  }

  private static func add(_ left: Int64, _ right: Int64) throws -> Int64 {
    let (sum, overflow) = left.addingReportingOverflow(right)
    guard !overflow else { throw AllocationError.overflow }
    return sum
  }
}
