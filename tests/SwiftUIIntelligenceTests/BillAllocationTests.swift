import Testing
import SwiftUIIntelligenceExamples

// Given minor-unit inputs, allocation either returns a complete bill or throws.
@Test(arguments: [
  (Int64(5), [Int64(2), 2, 1]),
  (Int64(1), [Int64(1), 0, 0]),
  (Int64(0), [Int64(0), 0, 0]),
]) func billItemsUseStableLargestRemainders(sample: (Int64, [Int64])) throws {
  let bill = try BillAllocation.allocate(.init(
    personIDs: ["c", "a", "b"],
    items: [.init(id: "meal", amount: sample.0, participantIDs: ["c", "b", "a"])],
    fee: 0
  ))
  #expect(bill.people.map(\.id) == ["a", "b", "c"])
  #expect(bill.people.map(\.food) == sample.1)
  #expect(bill.people.map { $0.itemShares } == sample.1.map { [.init(itemID: "meal", amount: $0)] })
  #expect(bill.people.map(\.total) == sample.1)
  #expect(bill.payable == sample.0)
}

// Given unequal food amounts or equal remainders, fees preserve exact proportional shares.
private let feeCases: [([Int64], Int64, [Int64])] = [
  ([1, 2, 3], 5, [1, 2, 2]),
  ([1, 1, 1], 2, [1, 1, 0]),
  ([0, 2, 0], 3, [0, 3, 0]),
  ([Int64.max / 4, Int64.max / 4, 0], Int64.max / 2, [Int64.max / 4 + 1, Int64.max / 4, 0]),
]

@Test(arguments: feeCases)
func billFeesUseExactProportions(sample: ([Int64], Int64, [Int64])) throws {
  let ids = ["a", "b", "c"]
  let items = ids.indices.map { BillAllocation.Item(id: ids[$0], amount: sample.0[$0], participantIDs: [ids[$0]]) }
  let bill = try BillAllocation.allocate(.init(personIDs: ids.reversed(), items: items.reversed(), fee: sample.1))
  #expect(bill.people.map(\.food) == sample.0)
  #expect(bill.people.map(\.fee) == sample.2)
  #expect(bill.people.map(\.total) == zip(sample.0, sample.2).map(+))
  #expect(bill.payable == sample.0.reduce(0, +) + sample.1)
}

// Given changed inputs and unseen group sizes, each calculation uses only its current input.
@Test func billRecalculatesForChangedInputsAndParticipantCounts() throws {
  for count in [1, 4, 7, 13] {
    let ids = (0..<count).map { "person-\($0)" }
    for amount: Int64 in [17, 101] {
      let input = BillAllocation.Input(personIDs: ids + ["observer"], items: [
        .init(id: "meal", amount: amount, participantIDs: ids.reversed()),
        .init(id: "empty", amount: 0, participantIDs: []),
      ], fee: 11)
      let bill = try BillAllocation.allocate(input)
      #expect(bill.payable == amount + 11)
      #expect(bill.people.reduce(Int64(0)) { $0 + $1.food } == amount)
      #expect(bill.people.reduce(Int64(0)) { $0 + $1.fee } == 11)
      #expect(bill.people.reduce(Int64(0)) { $0 + $1.total } == bill.payable)
      #expect(bill.people.first { $0.id == "observer" } == .init(id: "observer", itemShares: [], food: 0, fee: 0, total: 0))
      let reversed = try BillAllocation.allocate(.init(personIDs: input.personIDs.reversed(), items: input.items.reversed(), fee: input.fee))
      #expect(bill == reversed)
    }
  }
}

// Given invalid input, no partial result is returned.
@Test func billRejectsInvalidInputs() {
  typealias Input = BillAllocation.Input
  typealias Item = BillAllocation.Item
  let cases: [(Input, BillAllocation.AllocationError)] = [
    (.init(personIDs: ["a", "a"], items: [], fee: 0), .duplicatePersonID("a")),
    (.init(personIDs: ["a"], items: [Item(id: "x", amount: 0, participantIDs: []), Item(id: "x", amount: 0, participantIDs: [])], fee: 0), .duplicateItemID("x")),
    (.init(personIDs: ["a"], items: [Item(id: "x", amount: -1, participantIDs: ["a"])], fee: 0), .negativeItemAmount("x")),
    (.init(personIDs: ["a"], items: [], fee: -1), .negativeFee),
    (.init(personIDs: ["a"], items: [Item(id: "x", amount: 1, participantIDs: [])], fee: 0), .missingParticipants("x")),
    (.init(personIDs: ["a"], items: [Item(id: "x", amount: 0, participantIDs: ["b"])], fee: 0), .unknownParticipant(itemID: "x", personID: "b")),
    (.init(personIDs: ["a"], items: [Item(id: "x", amount: 0, participantIDs: ["a", "a"])], fee: 0), .duplicateParticipant(itemID: "x", personID: "a")),
    (.init(personIDs: ["a"], items: [], fee: 1), .feeWithoutFood),
    (.init(personIDs: ["a"], items: [Item(id: "x", amount: Int64.max, participantIDs: ["a"]), Item(id: "y", amount: 1, participantIDs: ["a"])], fee: 0), .overflow),
    (.init(personIDs: ["a"], items: [Item(id: "x", amount: Int64.max, participantIDs: ["a"])], fee: 1), .overflow),
  ]
  for (input, error) in cases {
    #expect(throws: error) { try BillAllocation.allocate(input) }
  }
}

@Test func billAllowsZeroAndMaximumPayableWithoutIntermediateOverflow() throws {
  let empty = try BillAllocation.allocate(.init(personIDs: [], items: [], fee: 0))
  #expect(empty == .init(people: [], payable: 0))
  let bill = try BillAllocation.allocate(.init(personIDs: ["b", "a"], items: [
    .init(id: "shared", amount: Int64.max - 2, participantIDs: ["b", "a"]),
  ], fee: 2))
  #expect(bill.people.map(\.food) == [Int64.max / 2, Int64.max / 2 - 1])
  #expect(bill.people.map(\.fee) == [1, 1])
  #expect(bill.payable == Int64.max)
}
