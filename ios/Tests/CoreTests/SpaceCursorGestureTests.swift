import XCTest
@testable import ThreePadCore

final class SpaceCursorGestureTests: XCTestCase {
    func testTapAndSmallJitterStillInsertSpace() {
        var g = SpaceCursorGesture(); g.begin(at: .zero)
        XCTAssertEqual(g.move(to: CGPoint(x: 8, y: 3)), 0)
        XCTAssertFalse(g.suppressesSpace)
    }
    func testHorizontalDragStepsAndReversesWithoutSpace() {
        var g = SpaceCursorGesture(); g.begin(at: .zero)
        XCTAssertEqual(g.move(to: CGPoint(x: -14, y: 0)), -1)
        XCTAssertEqual(g.move(to: CGPoint(x: -38, y: 0)), -2)
        XCTAssertEqual(g.move(to: CGPoint(x: -26, y: 0)), 1)
        XCTAssertEqual(g.move(to: .zero), 2)
        XCTAssertTrue(g.suppressesSpace)
        g.begin(at: .zero)
        XCTAssertFalse(g.suppressesSpace)
    }
    func testVerticalEscapeAndCancellationNeverInsertSpace() {
        var g = SpaceCursorGesture(); g.begin(at: .zero)
        XCTAssertEqual(g.move(to: CGPoint(x: 3, y: 30)), 0)
        XCTAssertEqual(g.move(to: CGPoint(x: 80, y: 30)), 0)
        XCTAssertTrue(g.suppressesSpace)
        g.cancel()
        XCTAssertEqual(g.move(to: CGPoint(x: -80, y: 0)), 0)
    }
}
