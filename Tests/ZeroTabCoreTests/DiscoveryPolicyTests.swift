import XCTest
@testable import ZeroTabCore

final class DiscoveryPolicyTests: XCTestCase {
    func testFoundTargetsDoNotRestartCursor() {
        var cursor = DiscoveryCursor()
        cursor.update(targets: [10, 20, 30])
        cursor.finishRound(nextID: 500, found: [10])
        cursor.update(targets: [20, 30])
        XCTAssertEqual(cursor.nextID, 500)
        XCTAssertEqual(cursor.rounds, 1)
    }

    func testNewPhysicalWindowRestartsDiscovery() {
        var cursor = DiscoveryCursor()
        cursor.update(targets: [10])
        cursor.finishRound(nextID: 600, found: [])
        cursor.update(targets: [10, 20])
        XCTAssertEqual(cursor.nextID, 0)
        XCTAssertEqual(cursor.rounds, 0)
    }

    func testBackgroundWorkStopsAtBudgetAndWhenResolved() {
        var cursor = DiscoveryCursor()
        cursor.update(targets: [10])
        for index in 1...8 { cursor.finishRound(nextID: UInt64(index * 100), found: []) }
        XCTAssertFalse(cursor.needsBackgroundWork)
        cursor.finishRound(nextID: 900, found: [10])
        XCTAssertFalse(cursor.needsBackgroundWork)
        XCTAssertTrue(cursor.targets.isEmpty)
    }

    func testRemoteTokenPreserves64BitIdentifierAndOwner() {
        let data = RemoteElementToken.make(pid: 1234, identifier: 0x0102030405060708)
        XCTAssertEqual(data.count, 20)
        XCTAssertEqual(Array(data[0..<4]), [0xd2, 0x04, 0, 0])
        XCTAssertEqual(Array(data[4..<8]), [0, 0, 0, 0])
        XCTAssertEqual(Array(data[8..<12]), [0x6f, 0x63, 0x6f, 0x63])
        XCTAssertEqual(Array(data[12..<20]), [8, 7, 6, 5, 4, 3, 2, 1])
    }
}
