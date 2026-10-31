import XCTest
@testable import ThreePadCore

final class OrderedTouchActionsTests: XCTestCase {
    func testReverseReleaseKeepsTouchDownOrder() {
        var queue = OrderedTouchActions<Int, String>()
        queue.begin(1); queue.begin(2)
        XCTAssertEqual(queue.finish(2, action: "ㅏ"), [])
        XCTAssertEqual(queue.finish(1, action: "ㄱ"), ["ㄱ", "ㅏ"])
        XCTAssertTrue(queue.isEmpty)
    }

    func testCancellationReleasesLaterCompletedInput() {
        var queue = OrderedTouchActions<Int, String>()
        queue.begin(1); queue.begin(2); queue.begin(3)
        XCTAssertEqual(queue.finish(2, action: "ㅏ"), [])
        XCTAssertEqual(queue.finish(1, action: nil), ["ㅏ"])
        XCTAssertFalse(queue.isEmpty)
        XCTAssertEqual(queue.finish(3, action: "ㄴ"), ["ㄴ"])
        XCTAssertTrue(queue.isEmpty)
    }

    func testIndependentSlideAndReverseReleaseComposeHangul() {
        var queue = OrderedTouchActions<Int, KeyboardAction>()
        var consonant = AnchoredGesture()
        var vowel = AnchoredGesture()
        let bounds = CGRect(x: 0, y: 0, width: 200, height: 200)
        let origin = CGPoint(x: 100, y: 100)
        let c = JoystickMapping.gridKeys(.c).first { $0.label == "ㄱ" }!
        let v = JoystickMapping.gridKeys(.v).first { $0.label == "ㅣ" }!
        consonant.begin(key: c, at: origin, bounds: bounds)
        vowel.begin(key: v, at: origin, bounds: bounds)
        queue.begin(1); queue.begin(2)
        let end = CGPoint(x: 140, y: 100)
        XCTAssertTrue(queue.finish(2, action: vowel.end(at: end)).isEmpty)
        let actions = queue.finish(1, action: consonant.end(at: origin))
        XCTAssertEqual(actions, [.jamo("ㄱ"), .jamo("ㅏ")])
    }
}
