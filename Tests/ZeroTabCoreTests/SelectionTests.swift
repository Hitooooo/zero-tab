import XCTest
@testable import ZeroTabCore

final class SelectionTests: XCTestCase {
    func testTabWrapsBothDirections() {
        var selection = Selection(count: 3)
        selection.cycle(-1); XCTAssertEqual(selection.index, 2)
        selection.cycle(1); XCTAssertEqual(selection.index, 0)
        selection.cycle(8); XCTAssertEqual(selection.index, 2)
    }

    func testHorizontalArrowsNeverCrossRows() {
        var selection = Selection(count: 10, columns: 4, index: 3)
        selection.move(.right); XCTAssertEqual(selection.index, 3)
        selection.move(.down); XCTAssertEqual(selection.index, 7)
        selection.move(.left); XCTAssertEqual(selection.index, 6)
    }

    func testLastRowClampsToNearestColumn() {
        var selection = Selection(count: 10, columns: 4, index: 7)
        selection.move(.down); XCTAssertEqual(selection.index, 9)
        selection.move(.down); XCTAssertEqual(selection.index, 9)
        selection.move(.up); XCTAssertEqual(selection.index, 5)
    }

    func testListNavigationAndEmptySelection() {
        var selection = Selection(count: 3, index: 0)
        selection.move(.left, linear: true); XCTAssertEqual(selection.index, 0)
        selection.move(.right, linear: true); XCTAssertEqual(selection.index, 1)
        var empty = Selection(count: 0)
        empty.cycle(-1); empty.move(.down); XCTAssertEqual(empty.index, 0)
    }

    func testSpaceGroupOverridesMRUAndUnknownIsNotOther() {
        let items = [
            RankedItem(id: "other", location: .other, attention: 100, ordinal: 0),
            RankedItem(id: "current-old", location: .current, attention: 1, ordinal: 1),
            RankedItem(id: "unknown", location: .unknown, attention: 200, ordinal: 2),
            RankedItem(id: "current-new", location: .current, attention: 2, ordinal: 3)
        ]
        XCTAssertEqual(CandidateOrder.sorted(items).map(\.id), ["current-new", "current-old", "other", "unknown"])
        XCTAssertEqual(items.first?.id, "other", "Sorting must not mutate the session's input snapshot")
    }

    func testEqualRanksKeepStableOrdinal() {
        let items = [RankedItem(id: 2, location: .current, attention: 0, ordinal: 2),
                     RankedItem(id: 1, location: .current, attention: 0, ordinal: 1)]
        XCTAssertEqual(CandidateOrder.sorted(items).map(\.id), [1, 2])
    }
}
