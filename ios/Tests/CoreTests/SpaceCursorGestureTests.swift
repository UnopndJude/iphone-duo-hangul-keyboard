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
    func testVerticalMovementLocksAxisAndCancelsSpace() {
        var g = SpaceCursorGesture(); g.begin(at: .zero)
        XCTAssertEqual(g.move(to: CGPoint(x: 3, y: -15)), 0)
        XCTAssertEqual(g.takeVerticalSteps(), -1)
        XCTAssertEqual(g.move(to: CGPoint(x: 80, y: -75)), 0)
        XCTAssertEqual(g.takeVerticalSteps(), -2)
        XCTAssertEqual(g.move(to: CGPoint(x: 80, y: -45)), 0)
        XCTAssertEqual(g.takeVerticalSteps(), 1)
        XCTAssertTrue(g.suppressesSpace)
        g.cancel()
        XCTAssertEqual(g.move(to: CGPoint(x: -80, y: 0)), 0)
        XCTAssertEqual(g.takeVerticalSteps(), 0)
    }

    func testLineOffsetsKeepColumnAndHandleEmoji() {
        XCTAssertEqual(CursorLine.offset(before: "가나다\nab", after: "c\n한🙂글", direction: -1), -4)
        XCTAssertEqual(CursorLine.offset(before: "가나다\nab", after: "c\n한🙂글", direction: 1), "c\n한🙂".utf16.count)
        XCTAssertEqual(CursorLine.offset(before: "가\nabcdef", after: "", direction: -1), -7)
        XCTAssertNil(CursorLine.offset(before: "한줄", after: "", direction: -1))
        XCTAssertNil(CursorLine.offset(before: nil, after: "\n다음", direction: 1))
    }
}
