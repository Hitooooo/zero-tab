import XCTest
@testable import ZeroTabCore

final class KeyboardStateTests: XCTestCase {
    func testQuickChordStillProducesOrderedBeginCommit() {
        var state = KeyboardState()
        XCTAssertEqual(state.keyDown(48, modifiers: .option, isRepeat: false).action, .begin(.windows, backwards: false))
        XCTAssertEqual(state.flagsChanged([]).action, .commit)
        XCTAssertTrue(state.keyUp(48).absorb, "Captured key-up must not leak after modifier release")
        XCTAssertNil(state.flagsChanged([]).action)
    }

    func testCancelLatchesUntilHoldReleased() {
        var state = KeyboardState()
        _ = state.keyDown(48, modifiers: .command, isRepeat: false)
        XCTAssertEqual(state.keyDown(53, modifiers: .command, isRepeat: false).action, .cancel)
        let repeated = state.keyDown(48, modifiers: .command, isRepeat: false)
        XCTAssertTrue(repeated.absorb); XCTAssertNil(repeated.action)
        XCTAssertNil(state.flagsChanged([]).action)
        XCTAssertEqual(state.keyDown(48, modifiers: .command, isRepeat: false).action, .begin(.applications, backwards: false))
    }

    func testShiftReleaseDoesNotCommit() {
        var state = KeyboardState()
        XCTAssertEqual(state.keyDown(48, modifiers: [.option, .shift], isRepeat: false).action, .begin(.windows, backwards: true))
        XCTAssertNil(state.flagsChanged(.option).action)
        XCTAssertEqual(state.keyDown(48, modifiers: .option, isRepeat: true).action, .cycle(1))
        XCTAssertEqual(state.flagsChanged([]).action, .commit)
    }

    func testUnrelatedKeysAndMixedModifiersPassThrough() {
        var state = KeyboardState()
        XCTAssertFalse(state.keyDown(0, modifiers: .command, isRepeat: false).absorb)
        XCTAssertFalse(state.keyDown(48, modifiers: [.command, .option], isRepeat: false).absorb)
        XCTAssertFalse(state.keyDown(48, modifiers: [.command, .control], isRepeat: false).absorb)
        XCTAssertFalse(state.keyDown(48, modifiers: [], isRepeat: false).absorb)
    }

    func testArrowInputAndReset() {
        var state = KeyboardState()
        _ = state.keyDown(48, modifiers: .option, isRepeat: false)
        XCTAssertEqual(state.keyDown(126, modifiers: .option, isRepeat: false).action, .move(.up))
        XCTAssertTrue(state.keyUp(126).absorb)
        state.reset()
        XCTAssertNil(state.flagsChanged([]).action)
        XCTAssertFalse(state.keyUp(48).absorb)
    }
}
