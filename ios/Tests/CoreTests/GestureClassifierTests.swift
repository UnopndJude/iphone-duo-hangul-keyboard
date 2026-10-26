import XCTest
import CoreGraphics
@testable import ThreePadCore

final class GestureClassifierTests: XCTestCase {
    private let origin = CGPoint(x: 100, y: 100)
    private let bounds = CGRect(x: 0, y: 0, width: 200, height: 200)
    private func point(_ angle: Double, _ distance: Double = 40) -> CGPoint {
        CGPoint(x: 100 + cos(angle * .pi / 180) * distance, y: 100 + sin(angle * .pi / 180) * distance)
    }
    private func gesture(_ pad: Pad = .c) -> GestureClassifier {
        var value = GestureClassifier()
        value.begin(pad: pad, at: origin, bounds: bounds)
        return value
    }

    func testNineChoicesOnBothCharacterPads() {
        let directions: [Direction] = [.e, .se, .s, .sw, .w, .nw, .n, .ne]
        for pad in [Pad.c, .v] {
            var tap = gesture(pad)
            XCTAssertEqual(tap.end(at: origin), .pad(pad, .tap))
            XCTAssertFalse(tap.active)
            for (index, direction) in directions.enumerated() {
                var value = gesture(pad)
                XCTAssertEqual(value.end(at: point(Double(index) * 45)), .pad(pad, direction))
                XCTAssertNil(value.end(at: point(Double(index) * 45)))
            }
        }
    }

    func testTapAndFlickDistanceBoundaries() {
        for (distance, expected) in [(0.0, Direction.tap), (9.0, .tap), (24.0, .e)] {
            var value = gesture()
            XCTAssertEqual(value.end(at: point(0, distance)), .pad(.c, expected))
        }
        for distance in [9.01, 15, 23.99] {
            var value = gesture()
            value.move(to: point(0, distance)); XCTAssertEqual(value.preview.kind, .uncertain)
            XCTAssertNil(value.end(at: point(0, distance)))
            XCTAssertEqual(value.preview.reason, "distance-dead-zone")
        }
    }

    func testAngularGuardGapsAcrossEveryBoundary() {
        for sector in 0..<8 {
            var value = gesture()
            let boundary = Double(sector) * 45 + 22.5
            XCTAssertNil(value.end(at: point(boundary)))
            XCTAssertEqual(value.preview.reason, "angle-gap")
            value = gesture()
            XCTAssertNotNil(value.end(at: point(Double(sector) * 45 + 17.5)))
            value = gesture()
            XCTAssertNil(value.end(at: point(Double(sector) * 45 + 17.51)))
        }
    }

    func testModifierOnlyAcceptsVerticalDirectionsAndTap() {
        for (angle, direction) in [(270.0, Direction.n), (240.0, .n), (300.0, .n), (90.0, .s), (60.0, .s), (120.0, .s)] {
            var value = gesture(.m)
            XCTAssertEqual(value.end(at: point(angle)), .pad(.m, direction))
        }
        for angle in [0.0, 45, 180, 225, 239.9, 300.1] {
            var value = gesture(.m)
            XCTAssertNil(value.end(at: point(angle)))
            XCTAssertEqual(value.preview.reason, "modifier-angle-gap")
        }
        var value = gesture(.m)
        XCTAssertEqual(value.end(at: origin), .pad(.m, .tap))
    }

    func testReturningToOriginDoesNotBecomeTap() {
        var value = gesture()
        value.move(to: point(0, 40))
        XCTAssertEqual(value.preview.direction, .e)
        XCTAssertNil(value.end(at: origin))
        XCTAssertEqual(value.preview.reason, "returned-to-origin")
        value = gesture()
        value.move(to: point(0, 12))
        XCTAssertNil(value.end(at: point(0, 3)))
    }

    func testPadMarginUsesEuclideanDistanceAndTerminalCancellation() {
        var value = gesture()
        XCTAssertNotNil(value.end(at: CGPoint(x: 248, y: 100)))
        value = gesture()
        value.move(to: CGPoint(x: 248.01, y: 100))
        XCTAssertNil(value.end(at: point(0)))
        XCTAssertEqual(value.preview.reason, "outside-pad-limit")
        value = gesture()
        // Outside the corner: each axis is under 48, but the total distance is over 48.
        value.move(to: CGPoint(x: 240, y: 240))
        XCTAssertNil(value.end(at: origin))
        XCTAssertEqual(value.preview.reason, "outside-pad-limit")
    }

    func testInvalidCoordinatesCancelAndCannotCommit() {
        var value = gesture()
        value.move(to: CGPoint(x: CGFloat.nan, y: 100))
        XCTAssertNil(value.end(at: origin))
        XCTAssertEqual(value.preview.reason, "invalid-coordinate")
        value = GestureClassifier()
        value.begin(pad: .c, at: origin, bounds: .zero)
        XCTAssertFalse(value.active)
        value.begin(pad: .c, at: CGPoint(x: -1, y: 0), bounds: bounds)
        XCTAssertFalse(value.active)
        XCTAssertEqual(value.preview.reason, "outside-start-pad")
    }

    func testCancelClearsActiveContactAndSubsequentRelease() {
        var value = gesture()
        value.cancel(reason: "orientation")
        XCTAssertFalse(value.active); XCTAssertEqual(value.preview.reason, "orientation")
        XCTAssertNil(value.end(at: origin))
        value.begin(pad: .v, at: origin, bounds: bounds)
        XCTAssertEqual(value.end(at: origin), .pad(.v, .tap))
    }

    func testRepeatedBeginDoesNotStealActivePad() {
        var value = gesture(.c)
        value.begin(pad: .v, at: CGPoint(x: 50, y: 50), bounds: bounds)
        XCTAssertEqual(value.end(at: origin), .pad(.c, .tap))
    }

    func testTouchOriginCanBeAnywhereOnPadIncludingBoundary() {
        for start in [CGPoint(x: 0, y: 0), CGPoint(x: 200, y: 200), CGPoint(x: 53, y: 142)] {
            var value = GestureClassifier()
            value.begin(pad: .c, at: start, bounds: bounds)
            XCTAssertEqual(value.end(at: CGPoint(x: start.x, y: start.y - 30)), .pad(.c, .n))
        }
    }
}
