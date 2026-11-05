import XCTest
@testable import ZeroTab

final class AppModelTests: XCTestCase {
    func testRefreshRestartsStoppedServiceWhenPermissionIsUnchanged() {
        let model = AppModel(accessibilityCheck: { true })
        var starts = 0
        model.onRefresh = {
            if !model.inputRunning {
                starts += 1
                model.inputRunning = true
            }
        }
        model.refresh()
        XCTAssertTrue(model.accessibilityGranted)
        XCTAssertEqual(starts, 1)

        // Sleep stops input without revoking permission. Wake must reconcile
        // the service even though AXIsProcessTrusted still returns true.
        model.inputRunning = false
        model.refresh()
        XCTAssertTrue(model.inputRunning)
        XCTAssertEqual(starts, 2)

        model.refresh()
        XCTAssertEqual(starts, 2, "A healthy service should be reused")
        model.onRefresh = nil
    }

    func testRefreshRechecksFailedServiceWithoutPermissionChange() {
        let model = AppModel(accessibilityCheck: { true })
        var attempts = 0
        model.onRefresh = { attempts += 1 }
        model.refresh()
        XCTAssertFalse(model.inputRunning)
        model.refresh()
        XCTAssertEqual(attempts, 2, "Reopening settings must retry a failed listener")
    }

    func testServiceRefreshSeesCurrentPermissionIncludingRevocation() {
        var trusted = true
        let model = AppModel(accessibilityCheck: { trusted })
        var permissions: [Bool] = []
        model.onRefresh = { permissions.append(model.accessibilityGranted) }
        model.refresh()
        trusted = false
        model.refresh()
        model.refresh()
        trusted = true
        model.refresh()
        XCTAssertEqual(permissions, [true, false, false, true])
        model.onRefresh = nil
    }
}
