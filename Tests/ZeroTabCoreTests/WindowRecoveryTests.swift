import XCTest
@testable import ZeroTabCore

final class WindowRecoveryTests: XCTestCase {
    func testRetainedButClosedWindowIsNotUsable() {
        XCTAssertTrue(WindowPresence.isNotPresented(location: .current, onScreen: false,
            minimized: false, applicationHidden: false))
    }

    func testMinimizedHiddenAndOtherDesktopRemainRestorable() {
        XCTAssertFalse(WindowPresence.isNotPresented(location: .current, onScreen: false,
            minimized: true, applicationHidden: false))
        XCTAssertFalse(WindowPresence.isNotPresented(location: .current, onScreen: false,
            minimized: false, applicationHidden: true))
        XCTAssertFalse(WindowPresence.isNotPresented(location: .other, onScreen: false,
            minimized: false, applicationHidden: false))
        XCTAssertFalse(WindowPresence.isNotPresented(location: .other, onScreen: false,
            minimized: false, applicationHidden: false, hasAssignedSpace: false))
    }

    func testUnknownVisibilityCannotProveClosed() {
        XCTAssertFalse(WindowPresence.isNotPresented(location: .unknown, onScreen: false,
            minimized: false, applicationHidden: false))
        XCTAssertFalse(WindowPresence.isNotPresented(location: .current, onScreen: nil,
            minimized: false, applicationHidden: false))
        XCTAssertFalse(WindowPresence.isNotPresented(location: .current, onScreen: true,
            minimized: false, applicationHidden: false))
        XCTAssertFalse(WindowPresence.isNotPresented(location: .current, onScreen: false,
            minimized: nil, applicationHidden: false))
    }

    func testKnownUnassignedSurfaceIsDifferentFromUnknownMembership() {
        XCTAssertTrue(WindowPresence.isNotPresented(location: .unknown, onScreen: false,
            minimized: false, applicationHidden: false, hasAssignedSpace: false))
        XCTAssertFalse(WindowPresence.isNotPresented(location: .unknown, onScreen: false,
            minimized: false, applicationHidden: false, hasAssignedSpace: nil))
        XCTAssertFalse(WindowPresence.isNotPresented(location: .unknown, onScreen: false,
            minimized: true, applicationHidden: false, hasAssignedSpace: false))
    }

    func testMissingVisibilityFieldUsesOnScreenInventoryWithoutDiscardingRestorableWindows() {
        let absent = WindowPresence.onScreen(reported: nil, appearsInOnScreenList: false)
        XCTAssertTrue(WindowPresence.isNotPresented(location: .unknown, onScreen: absent,
            minimized: false, applicationHidden: false, hasAssignedSpace: false))
        XCTAssertFalse(WindowPresence.isNotPresented(location: .other, onScreen: absent,
            minimized: false, applicationHidden: false, hasAssignedSpace: true))
        XCTAssertFalse(WindowPresence.isNotPresented(location: .current, onScreen: absent,
            minimized: true, applicationHidden: false))
        XCTAssertFalse(WindowPresence.isNotPresented(location: .current, onScreen: absent,
            minimized: false, applicationHidden: true))
        let failed = WindowPresence.onScreen(reported: nil, appearsInOnScreenList: nil)
        XCTAssertNil(failed)
        XCTAssertFalse(WindowPresence.isNotPresented(location: .unknown, onScreen: failed,
            minimized: false, applicationHidden: false, hasAssignedSpace: false))
        let present = WindowPresence.onScreen(reported: nil, appearsInOnScreenList: true)
        XCTAssertFalse(WindowPresence.isNotPresented(location: .current, onScreen: present,
            minimized: false, applicationHidden: false))
    }
}
