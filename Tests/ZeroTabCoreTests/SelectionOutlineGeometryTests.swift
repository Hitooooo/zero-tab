import XCTest
import CoreGraphics
@testable import ZeroTabCore

final class SelectionOutlineGeometryTests: XCTestCase {
    func testStrokeHasEqualWidthOnAllFourSides() {
        for size in [56.0, 104.0] {
            let shape = SelectionOutlineGeometry(bounds: CGRect(x: 0, y: 0, width: size, height: size))
            let inset = shape.lineWidth / 2
            XCTAssertEqual(shape.pathRect.minX - shape.outerRect.minX, inset, accuracy: 0.001)
            XCTAssertEqual(shape.pathRect.minY - shape.outerRect.minY, inset, accuracy: 0.001)
            XCTAssertEqual(shape.outerRect.maxX - shape.pathRect.maxX, inset, accuracy: 0.001)
            XCTAssertEqual(shape.outerRect.maxY - shape.pathRect.maxY, inset, accuracy: 0.001)
            XCTAssertGreaterThan(shape.cornerRadius - inset, 0)
        }
    }

    func testRectangularProposalKeepsOutlineSquareAndCentered() {
        let bounds = CGRect(x: 0, y: 0, width: 120, height: 104)
        let shape = SelectionOutlineGeometry(bounds: bounds)
        XCTAssertEqual(shape.outerRect.width, shape.outerRect.height)
        XCTAssertEqual(shape.outerRect.midX, bounds.midX)
        XCTAssertEqual(shape.outerRect.midY, bounds.midY)
        XCTAssertEqual(shape.pathRect.midX, bounds.midX)
        XCTAssertEqual(shape.pathRect.midY, bounds.midY)
    }
}
