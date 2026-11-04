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

    func testBadgesPreserveTopologyOrderAndDoNotGuessPartialMembership() {
        let spaces = SpaceTopology(visible: [801], known: [801, 4, 90], order: [801, 4, 90],
            badges: [801: "①", 4: "②"])
        XCTAssertEqual(spaces.badge(of: [4]), "②")
        XCTAssertEqual(spaces.badge(of: [801, 4]), "①/②")
        XCTAssertNil(spaces.badge(of: nil))
        XCTAssertNil(spaces.badge(of: []))
        XCTAssertNil(spaces.badge(of: [801, 999]))
        XCTAssertNil(spaces.badge(of: [801, 90]))
    }

    func testBadgeNumbersDistinguishDisplaysAndFullscreenSpaces() {
        XCTAssertEqual(SpaceBadge.label(number: 1), "①")
        XCTAssertEqual(SpaceBadge.label(number: 2), "②")
        XCTAssertEqual(SpaceBadge.label(number: 20), "⑳")
        XCTAssertEqual(SpaceBadge.label(number: 21), "㉑")
        XCTAssertEqual(SpaceBadge.label(number: 50), "㊿")
        XCTAssertEqual(SpaceBadge.label(number: 51), "(51)")
        XCTAssertEqual(SpaceBadge.label(number: 2, display: 1), "1·②")
        XCTAssertEqual(SpaceBadge.label(number: 1, display: 2, fullscreen: true), "2·全①")
    }
}
