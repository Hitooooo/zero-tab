import XCTest
@testable import ZeroTabCore

final class SpaceMembershipTests: XCTestCase {
    let topology = SpaceTopology(visible: [1, 4], known: [1, 2, 3, 4, 5])

    func testCurrentSpacesAcrossDisplaysAndPinnedWindows() {
        XCTAssertEqual(topology.location(of: [1]), .current)
        XCTAssertEqual(topology.location(of: [4]), .current)
        XCTAssertEqual(topology.location(of: [1, 2, 3, 4, 5]), .current)
    }

    func testConfirmedOtherSpace() {
        XCTAssertEqual(topology.location(of: [2]), .other)
        XCTAssertEqual(topology.location(of: [2, 5]), .other)
    }

    func testUnknownAndTransientTopologyAreNotOtherSpace() {
        XCTAssertEqual(topology.location(of: nil), .unknown)
        XCTAssertEqual(topology.location(of: []), .unknown)
        XCTAssertEqual(topology.location(of: [99]), .unknown)
        XCTAssertEqual(SpaceTopology(visible: [], known: [1]).location(of: [1]), .unknown)
    }

    func testLabelsUseDesktopOrderRatherThanInternalSpaceIDs() {
        let spaces = SpaceTopology(visible: [801], known: [801, 4],
            labels: [801: "桌面 1", 4: "桌面 2"], order: [801, 4])
        XCTAssertEqual(spaces.label(of: [4]), "桌面 2")
        XCTAssertEqual(spaces.label(of: [801, 4]), "桌面 1、桌面 2")
        XCTAssertNil(spaces.label(of: [999]))
    }
}
