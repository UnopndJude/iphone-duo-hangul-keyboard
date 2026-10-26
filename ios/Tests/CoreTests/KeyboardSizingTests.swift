import XCTest
@testable import ThreePadCore

final class KeyboardSizingTests: XCTestCase {
    func testShortScreensShrinkWithoutSacrificingTouchGeometry() {
        for screenHeight: CGFloat in [320, 568, 667, 740, 844, 932, 1200] {
            for width: CGFloat in [320, 375, 390, 430, 600, 900, 1200] {
                for bottom: CGFloat in [0, 21, 34] {
                    let height = KeyboardSizing.contentHeight(screenHeight: screenHeight, bottomInset: bottom)
                    // Extension's child ends above the system bottom safe area.
                    let m = KeyboardSizing.metrics(width: width - 12, height: height, bottomInset: 0)
                    XCTAssertGreaterThanOrEqual(height, 220)
                    XCTAssertLessThanOrEqual(height + bottom, 320)
                    XCTAssertGreaterThanOrEqual(m.diameter, 140)
                    XCTAssertEqual(m.barHeight, 44)
                    XCTAssertGreaterThanOrEqual(m.barY - (m.padY + m.reserved + m.diameter), 6)
                    let inputArea = CGRect(x: 6, y: m.padY, width: width - 12, height: height - m.bottom - m.padY)
                    for frames in [EnglishLayout.make(in: inputArea, needsGlobe: true).frames,
                                   SymbolLayout.make(in: inputArea, needsGlobe: true).frames] {
                        XCTAssertFalse(frames.isEmpty)
                        for frame in frames.values {
                            XCTAssertGreaterThanOrEqual(frame.height, 44)
                            XCTAssertGreaterThan(frame.width, 0)
                            XCTAssertGreaterThanOrEqual(frame.minY, inputArea.minY)
                            XCTAssertLessThanOrEqual(frame.maxY, inputArea.maxY + 0.001)
                        }
                    }
                }
            }
        }
    }

    func testSmallScreenRemovesChromeBeforeShrinkingCircles() {
        let height = KeyboardSizing.contentHeight(screenHeight: 667, bottomInset: 34)
        XCTAssertEqual(height, 220)
        let m = KeyboardSizing.metrics(width: 363, height: height, bottomInset: 0)
        XCTAssertEqual(m.header, 0)
        XCTAssertFalse(m.showQuickSymbols)
        XCTAssertEqual(m.reserved, 0)
        XCTAssertGreaterThanOrEqual(m.diameter, 140)
        let large = KeyboardSizing.metrics(width: 888, height: 300, bottomInset: 0)
        XCTAssertEqual(large.header, 24)
        XCTAssertTrue(large.showQuickSymbols)
    }

    func testConsonantAndVowelCentersRemainSelectableAtMinimumSize() {
        let rect = CGRect(x: 0, y: 0, width: 147, height: 147)
        for pad in [Pad.c, .v] {
            for (index, key) in JoystickMapping.keys(pad).enumerated() {
                let center = JoystickMapping.center(pad: pad, index: index, bounds: rect)
                // A 16pt-wide patch around each glyph remains the same key.
                for dx: CGFloat in [-8, 0, 8] {
                    for dy: CGFloat in [-8, 0, 8] {
                        XCTAssertEqual(JoystickMapping.key(pad: pad, at: CGPoint(x: center.x + dx, y: center.y + dy), bounds: rect)?.label, key.label)
                    }
                }
            }
        }
    }
}
