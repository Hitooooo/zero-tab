import XCTest
@testable import ZeroTabCore

final class WindowAdmissionTests: XCTestCase {
    func testChromeDocumentsRemainButUntitledHelpersDoNot() {
        XCTAssertTrue(WindowAdmission.accepts(isChrome: true, remoteOnly: false, standardWindow: true, hasTitle: true))
        XCTAssertTrue(WindowAdmission.accepts(isChrome: true, remoteOnly: true, standardWindow: true, hasTitle: true))
        XCTAssertFalse(WindowAdmission.accepts(isChrome: true, remoteOnly: true, standardWindow: true, hasTitle: false))
        XCTAssertFalse(WindowAdmission.accepts(isChrome: true, remoteOnly: false, standardWindow: false, hasTitle: true))
    }

    func testUntitledNativeWindowIsDifferentFromUnconfirmedRemoteSurface() {
        XCTAssertTrue(WindowAdmission.accepts(isChrome: false, remoteOnly: false, standardWindow: true, hasTitle: false))
        XCTAssertFalse(WindowAdmission.accepts(isChrome: false, remoteOnly: true, standardWindow: true, hasTitle: false))
        XCTAssertFalse(WindowAdmission.accepts(isChrome: false, remoteOnly: true, standardWindow: false, hasTitle: true))
        XCTAssertTrue(WindowAdmission.accepts(isChrome: false, remoteOnly: true, standardWindow: true, hasTitle: true))
    }
}
