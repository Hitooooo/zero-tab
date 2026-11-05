import XCTest
import CoreGraphics
@testable import ZeroTabCore

final class SelectionBackgroundGeometryTests: XCTestCase {
    func testRectangularProposalKeepsBackgroundSquareAndCentered() {
        let bounds = CGRect(x: 0, y: 0, width: 120, height: 104)
        let shape = SelectionBackgroundGeometry(bounds: bounds)
        XCTAssertEqual(shape.rect.width, shape.rect.height)
        XCTAssertEqual(shape.rect.midX, bounds.midX)
        XCTAssertEqual(shape.rect.midY, bounds.midY)
    }
}
