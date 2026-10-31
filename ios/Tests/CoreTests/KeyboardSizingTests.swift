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
        XCTAssertEqual(large.reserved, 0)
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

final class DismissKeyLayoutTests: XCTestCase {
    func testDismissFitsWithoutOverlapAcrossModesAndWidths() {
        for width: CGFloat in [308, 363, 588, 600, 900] {
            for globe in [false, true] {
                let area = CGRect(x: 6, y: 4, width: width, height: 210)
                for frames in [EnglishLayout.make(in: area, needsGlobe: globe, needsDismiss: true).frames,
                               SymbolLayout.make(in: area, needsGlobe: globe, needsDismiss: true).frames] {
                    guard let dismiss = frames["dismiss"], let space = frames["space"] else {
                        XCTFail("Missing dismiss or space"); continue
                    }
                    XCTAssertGreaterThanOrEqual(dismiss.width, 25)
                    XCTAssertEqual(dismiss.height, 44)
                    XCTAssertGreaterThanOrEqual(space.width, 63.999)
                    XCTAssertLessThanOrEqual(dismiss.maxX, area.maxX + 0.001)
                    for (key, frame) in frames where key != "dismiss" {
                        XCTAssertFalse(dismiss.intersects(frame), "\(width) \(key)")
                    }
                }
            }
        }
    }
}

final class CompactHangulGridTests: XCTestCase {
    func testDingulScreenshotDigitsAndSymbols() {
        let keys = Dictionary(uniqueKeysWithValues: JoystickMapping.gridConsonants.map { ($0.label, $0) })
        let digits: [(String, Direction, String)] = [
            ("ㅅ", .w, "1"), ("ㅅ", .s, "2"), ("ㅅ", .e, "3"),
            ("ㅇ", .w, "4"), ("ㅇ", .s, "5"), ("ㅇ", .e, "6"),
            ("ㅎ", .w, "7"), ("ㅎ", .s, "8"), ("ㅎ", .e, "9"), ("ㅎ", .n, "0"),
            ("ㄱ", .s, "#"), ("ㄹ", .n, "^"), ("ㄹ", .w, "="), ("ㄹ", .e, "-"), ("ㄹ", .s, "_"),
            ("ㅇ", .n, "❤️"), ("ㅈ", .s, "~")
        ]
        for (label, direction, value) in digits { XCTAssertEqual(keys[label]?.action(direction), .literal(value)) }
        var model = ThreePadModel()
        for action in [keys["ㅎ"]!.action(.tap)!, .jamo("ㅏ"), keys["ㄴ"]!.action(.tap)!] { XCTAssertTrue(model.apply(action)) }
        XCTAssertEqual(model.text, "한")
    }

    func testDingulRowOrder() {
        let area = CGRect(x: 0, y: 0, width: 160, height: 200)
        XCTAssertEqual(JoystickMapping.gridFrames(pad: .c, bounds: area).map { $0.key.label }, ["ㄱ", "ㄴ", "ㄹ", "ㅁ", "ㅅ", "ㅇ", "ㅈ", "ㅎ"])
        XCTAssertEqual(JoystickMapping.gridFrames(pad: .v, bounds: area).map { $0.key.label }, ["ㅢ", "ㅣ", "?", "ㅡ", ".", "··", "/"])
        XCTAssertEqual(JoystickMapping.gridControlFrame(in: area), CGRect(x: 100, y: 0, width: 60, height: 50))
    }

    func testEveryCellHasLargeTargetsAndNoDeadStartAreas() {
        for width: CGFloat in [320, 375, 390, 430, 599] {
            for height: CGFloat in [238, 250, 286, 320] {
                let m = KeyboardSizing.metrics(width: width - 12, height: height, bottomInset: 0)
                let unit = (width - 18) / 3.6
                for pad in [Pad.c, .v] {
                    let bank = CGRect(x: 6, y: m.padY, width: unit * (pad == .c ? 2 : 1.6), height: m.padHeight)
                    let cells = JoystickMapping.gridFrames(pad: pad, bounds: bank)
                    XCTAssertEqual(Set(cells.map { $0.key.label }), Set(JoystickMapping.keys(pad).map(\.label) + (pad == .c ? ["ㅎ"] : [])))
                    for cell in cells {
                        XCTAssertEqual(cell.frame.width, unit * (pad == .v && cell.frame.minX > bank.minX ? 0.6 : 1), accuracy: 0.001)
                        XCTAssertEqual(cell.frame.height, bank.height / 4, accuracy: 0.001)
                        XCTAssertGreaterThanOrEqual(cell.frame.width, 44)
                        XCTAssertGreaterThanOrEqual(cell.frame.height, 44)
                        let point = CGPoint(x: cell.frame.midX, y: cell.frame.midY)
                        XCTAssertEqual(JoystickMapping.gridKey(pad: pad, at: point, bounds: bank)?.label, cell.key.label)
                        for direction in JoystickMapping.directions.map(\.0) + [.tap] {
                            var gesture = AnchoredGesture()
                            gesture.begin(key: cell.key, at: point, bounds: bank)
                            let end = CGPoint(x: point.x + (direction == .e ? 30 : direction == .w ? -30 : 0),
                                              y: point.y + (direction == .s ? 30 : direction == .n ? -30 : 0))
                            XCTAssertEqual(gesture.end(at: end), cell.key.action(direction))
                        }
                    }
                    for x in stride(from: bank.minX + 0.5, to: bank.maxX, by: 4) {
                        for y in stride(from: bank.minY + 0.5, to: bank.maxY, by: 4) {
                            let point = CGPoint(x: x, y: y)
                            if pad == .c || !JoystickMapping.gridControlFrame(in: bank).contains(point) {
                                XCTAssertNotNil(JoystickMapping.gridKey(pad: pad, at: point, bounds: bank))
                            }
                        }
                    }
                }
            }
        }
        XCTAssertTrue(JoystickMapping.usesGrid(keyboardWidth: 599))
        XCTAssertFalse(JoystickMapping.usesGrid(keyboardWidth: 600))
    }
}
