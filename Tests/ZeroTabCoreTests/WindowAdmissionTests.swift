import XCTest
@testable import ZeroTabCore

final class WindowAdmissionTests: XCTestCase {
    func testPublishedUntitledWindowsAndDialogsRemainSelectable() {
        XCTAssertTrue(WindowAdmission.accepts(isPublished: true, standardWindow: true, hasTitle: false))
        XCTAssertTrue(WindowAdmission.accepts(isPublished: true, standardWindow: false, hasTitle: true))
    }

    func testSupplementalHintsAndRemoteHandlesNeedNamedStandardWindows() {
        XCTAssertFalse(WindowAdmission.accepts(isPublished: false, standardWindow: true, hasTitle: false))
        XCTAssertFalse(WindowAdmission.accepts(isPublished: false, standardWindow: false, hasTitle: true))
        XCTAssertTrue(WindowAdmission.accepts(isPublished: false, standardWindow: true, hasTitle: true))
    }
}
