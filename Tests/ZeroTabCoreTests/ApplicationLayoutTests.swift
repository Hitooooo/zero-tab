import XCTest
@testable import ZeroTabCore

final class ApplicationLayoutTests: XCTestCase {
    func testThirteenAppsUseSpaceForLargeIcons() {
        let layout = ApplicationLayout(count: 13, maxWidth: 1400, maxHeight: 600, wrap: false)
        XCTAssertGreaterThan(layout.iconSize, 96)
        XCTAssertEqual(layout.width, 1400, accuracy: 0.001)
        XCTAssertLessThanOrEqual(layout.height, 148)
        XCTAssertEqual(layout.cellWidth * 13 + ApplicationLayout.iconGap * 12 + ApplicationLayout.padding * 2, layout.width, accuracy: 0.001)
    }

    func testCrowdedRowScrollsInsteadOfMakingIconsTiny() {
        let layout = ApplicationLayout(count: 40, maxWidth: 1200, maxHeight: 600, wrap: false)
        XCTAssertGreaterThanOrEqual(layout.iconSize, 56)
        XCTAssertLessThanOrEqual(layout.width, 1200)
        XCTAssertGreaterThan(layout.cellWidth * 40, layout.width)
    }

    func testWrappedIncompleteRowFitsAndUsesWholeCells() {
        let layout = ApplicationLayout(count: 13, maxWidth: 1200, maxHeight: 600, wrap: true)
        XCTAssertEqual(layout.columns, 10)
        XCTAssertLessThanOrEqual(layout.width, 1200)
        XCTAssertEqual(layout.height, layout.cellHeight * 2 + ApplicationLayout.rowSpacing + ApplicationLayout.padding * 2)
    }

    func testTallGridIsCappedForScrolling() {
        let layout = ApplicationLayout(count: 100, maxWidth: 800, maxHeight: 400, wrap: true)
        XCTAssertEqual(layout.height, 400)
        XCTAssertLessThanOrEqual(layout.width, 800)
    }

    func testSingleAndEmptyListsHaveUsableGeometry() {
        for count in [0, 1] {
            let layout = ApplicationLayout(count: count, maxWidth: 300, maxHeight: 500, wrap: false)
            XCTAssertEqual(layout.columns, 1)
            XCTAssertEqual(layout.iconSize, 104)
            XCTAssertEqual(layout.width, layout.cellWidth + ApplicationLayout.padding * 2)
            XCTAssertEqual(layout.height, layout.cellHeight + ApplicationLayout.padding * 2)
        }
    }

    func testCaptionDoesNotOffsetIconRowFromPanelCenter() {
        let layout = ApplicationLayout(count: 13, maxWidth: 1400, maxHeight: 600, wrap: false)
        let top = ApplicationLayout.padding
        let bottom = layout.height - top - layout.iconSize
        XCTAssertEqual(top, bottom, accuracy: 0.001)
        XCTAssertEqual(top + layout.iconSize / 2, layout.height / 2, accuracy: 0.001)
        XCTAssertEqual(layout.cellHeight, layout.iconSize)
        XCTAssertLessThanOrEqual(ApplicationLayout.nameHeight, bottom)
        let captionBottom = layout.cellHeight + ApplicationLayout.nameHeight - ApplicationLayout.captionOverlap
        XCTAssertLessThan(captionBottom, layout.height - top, "Caption must retain breathing room above the panel edge")
    }
    func testAllFourInsetsMatchForRowAndGrid() {
        for wrap in [false, true] {
            let layout = ApplicationLayout(count: 13, maxWidth: 1400, maxHeight: 1000, wrap: wrap)
            let contentWidth = Double(layout.columns) * layout.iconSize + Double(layout.columns - 1) * ApplicationLayout.iconGap
            let rows = (13 + layout.columns - 1) / layout.columns
            let contentHeight = Double(rows) * layout.iconSize + Double(rows - 1) * ApplicationLayout.rowSpacing
            let right = layout.width - ApplicationLayout.padding - contentWidth
            let bottom = layout.height - ApplicationLayout.padding - contentHeight
            XCTAssertEqual(right, ApplicationLayout.padding, accuracy: 0.001)
            XCTAssertEqual(bottom, ApplicationLayout.padding, accuracy: 0.001)
            XCTAssertEqual(layout.cellWidth, layout.iconSize, "Icon spacing must not add a hidden outer inset")
        }
    }

}
