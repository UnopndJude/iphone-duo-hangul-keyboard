import XCTest
@testable import ThreePadCore

final class AnchoredGestureTests: XCTestCase {
    let bounds = CGRect(x: 10, y: 20, width: 240, height: 240)
    func start(_ pad: Pad, _ label: String, in rect: CGRect? = nil) -> CGPoint {
        let index = JoystickMapping.keys(pad).firstIndex { $0.label == label }!
        return JoystickMapping.center(pad: pad, index: index, bounds: rect ?? bounds)
    }
    func input(_ pad: Pad, _ label: String, dx: CGFloat = 0, dy: CGFloat = 0) -> KeyboardAction? {
        var gesture = AnchoredGesture()
        let point = start(pad, label)
        gesture.begin(pad: pad, at: point, bounds: bounds)
        return gesture.end(at: CGPoint(x: point.x + dx, y: point.y + dy))
    }
    func punctuationInput(_ key: JoystickMapping.Key, dx: CGFloat = 0, dy: CGFloat = 0) -> KeyboardAction? {
        var gesture = AnchoredGesture()
        let rect = CGRect(x: 40, y: 50, width: 84, height: 44)
        let point = CGPoint(x: rect.midX, y: rect.midY)
        gesture.begin(key: key, at: point, bounds: rect)
        return gesture.end(at: CGPoint(x: point.x + dx, y: point.y + dy))
    }
    func testEveryVisibleTapAndCardinalOutput() {
        for pad in [Pad.c, .v] {
            for key in JoystickMapping.keys(pad) {
                for (direction, dx, dy) in [(Direction.tap, 0.0, 0.0), (.n,0,-30), (.s,0,30), (.w,-30,0), (.e,30,0)] {
                    let expected = key.outputs[direction].map { value -> KeyboardAction in
                        HangulComposer.initials.contains(value) || HangulComposer.vowels.contains(value) ? .jamo(value) : .literal(value)
                    }
                    XCTAssertEqual(input(pad, key.label, dx: dx, dy: dy), expected, "\(key.label) \(direction)")
                }
            }
        }
    }
    func testDigitsOccupyOnlyPreviouslyUnusedDirections() {
        let paths: [(String, CGFloat, CGFloat, String)] = [
            ("ㄹ", 0, -30, "1"), ("ㄹ", -30, 0, "2"), ("ㄹ", 30, 0, "3"), ("ㄹ", 0, 30, "4"),
            ("ㄱ", 0, 30, "5"), ("ㅇ", 0, -30, "6"), ("ㅇ", 0, 30, "7"),
            ("ㅅ", -30, 0, "8"), ("ㅅ", 30, 0, "9"), ("ㅅ", 0, 30, "0")
        ]
        for (key, dx, dy, digit) in paths {
            XCTAssertEqual(input(.c, key, dx: dx, dy: dy), .literal(digit))
        }
        XCTAssertEqual(Set(paths.map { $0.3 }), Set("0123456789".map(String.init)))
        for (key, value) in [("ㄱ", "ㅋ"), ("ㄴ", "ㅌ"), ("ㅁ", "ㅍ"), ("ㅇ", "ㅎ"), ("ㅈ", "ㅊ")] {
            XCTAssertEqual(input(.c, key, dx: -30), .jamo(value))
            XCTAssertEqual(input(.c, key, dx: 30), .jamo(value))
        }
    }

    func testPunctuationAlternatesWithUnmovedVowels() {
        XCTAssertEqual(JoystickMapping.ringKeys(.v).map(\.label), ["ㅢ", ".", "ㅡ", "?", "··", "/"])
        for (label, index) in [("ㅢ", 0), ("ㅡ", 2), ("··", 4)] {
            let point = start(.v, label)
            let angle = -CGFloat.pi / 2 + CGFloat(index) * .pi / 3
            let radius = bounds.width * 0.35
            XCTAssertEqual(point.x, bounds.midX + cos(angle) * radius, accuracy: 0.001)
            XCTAssertEqual(point.y, bounds.midY + sin(angle) * radius, accuracy: 0.001)
        }
        for key in JoystickMapping.punctuation {
            for (direction, dx, dy) in [(Direction.tap, 0.0, 0.0), (.n, 0, -30), (.s, 0, 30), (.w, -30, 0), (.e, 30, 0)] {
                XCTAssertEqual(input(.v, key.label, dx: dx, dy: dy), key.action(direction), "\(key.label) \(direction)")
            }
        }
    }

    func testMergedIeungHieuhAndComposition() {
        XCTAssertEqual(JoystickMapping.consonants.count, 7)
        XCTAssertEqual(JoystickMapping.vowels.count, 4)
        XCTAssertFalse(JoystickMapping.consonants.contains { $0.label == "ㅎ" })
        XCTAssertEqual(input(.c,"ㅇ"), .jamo("ㅇ"))
        XCTAssertEqual(input(.c,"ㅇ",dx:-30), .jamo("ㅎ"))
        XCTAssertEqual(input(.c,"ㅇ",dx:30), .jamo("ㅎ"))
        XCTAssertEqual(input(.c,"ㅇ",dy:-30), .literal("6"))
        var model = ThreePadModel()
        for action in [input(.c,"ㅇ",dx:30)!, input(.v,"ㅣ",dx:30)!, input(.c,"ㄴ")!] { model.apply(action) }
        XCTAssertEqual(model.text,"한")
        model.apply(.delete); XCTAssertEqual(model.text,"하")
        model.apply(.delete); XCTAssertEqual(model.text,"ㅎ")
        model.apply(.delete); XCTAssertEqual(model.text,"")
    }
    func testOfficialDingulExamples() {
        XCTAssertEqual(input(.c,"ㅈ",dy:-30), .jamo("ㅉ"))
        XCTAssertEqual(input(.c,"ㅈ",dx:-30), .jamo("ㅊ"))
        XCTAssertEqual(input(.c,"ㅈ",dx:30), .jamo("ㅊ"))
        XCTAssertEqual(input(.c,"ㅈ",dy:30), .literal("~"))
        XCTAssertEqual(input(.c,"ㄱ",dy:-30), .jamo("ㄲ"))
        XCTAssertEqual(input(.c,"ㄱ",dx:30), .jamo("ㅋ"))
        XCTAssertEqual(input(.c,"ㄴ",dy:30), .jamo("ㄷ"))
        XCTAssertEqual(input(.v,"ㅣ",dx:30), .jamo("ㅏ"))
        XCTAssertEqual(input(.v,"ㅢ",dx:-30), .jamo("ㅝ"))
        XCTAssertEqual(input(.v,"ㅡ",dy:-30), .jamo("ㅙ"))
        XCTAssertNil(input(.v,"··"))
    }
    func testCrossingToNeighbourKeepsStartingKey() {
        // ㄱ starts at top, moving right toward ㄴ still yields ㅋ.
        XCTAssertEqual(input(.c,"ㄱ",dx:80), .jamo("ㅋ"))
    }
    func testReturnDiagonalDeadZoneCancelButLongSlideCommits() {
        var gesture = AnchoredGesture()
        let point = start(.c,"ㄱ")
        gesture.begin(pad: .c, at: point, bounds: bounds)
        gesture.move(to: CGPoint(x: point.x + 30, y: point.y))
        XCTAssertNil(gesture.end(at: point))
        XCTAssertNil(input(.c,"ㄱ",dx:30,dy:30))
        XCTAssertNil(input(.c,"ㄱ",dx:16))
        XCTAssertEqual(input(.c,"ㄱ",dx:400), .jamo("ㅋ"))
    }

    func testEveryMappedDirectionSupportsLongSlidesAcrossScreenSizes() {
        for diameter: CGFloat in [140, 180, 240, 280] {
            let rect = CGRect(x: 10, y: 20, width: diameter, height: diameter)
            for pad in [Pad.c, .v] {
                for key in JoystickMapping.keys(pad) {
                    for (direction, _) in JoystickMapping.directions {
                        var gesture = AnchoredGesture()
                        let p = start(pad, key.label, in: rect)
                        gesture.begin(pad: pad, at: p, bounds: rect)
                        let dx: CGFloat = direction == .e ? 400 : direction == .w ? -400 : 0
                        let dy: CGFloat = direction == .s ? 400 : direction == .n ? -400 : 0
                        XCTAssertEqual(gesture.end(at: CGPoint(x: p.x + dx, y: p.y + dy)), key.action(direction), "\(diameter) \(key.label) \(direction)")
                    }
                }
            }
        }
    }

    func testWiderAnglesShorterFlicksAndDirectionRetention() {
        XCTAssertEqual(input(.c, "ㅈ", dx: 18), .jamo("ㅊ"))
        XCTAssertEqual(input(.c, "ㅈ", dx: 30, dy: 20), .jamo("ㅊ"))
        var gesture = AnchoredGesture()
        let p = start(.c, "ㅈ")
        gesture.begin(pad: .c, at: p, bounds: bounds)
        gesture.move(to: CGPoint(x: p.x + 30, y: p.y))
        gesture.move(to: CGPoint(x: p.x + 400, y: p.y + 400))
        XCTAssertEqual(gesture.candidate, "ㅊ")
        // A clear turn still lets the user correct their chosen direction.
        gesture.move(to: CGPoint(x: p.x, y: p.y - 60))
        XCTAssertEqual(gesture.candidate, "ㅉ")
        XCTAssertEqual(gesture.end(at: CGPoint(x: p.x, y: p.y - 60)), .jamo("ㅉ"))
        gesture.begin(pad: .c, at: p, bounds: bounds)
        gesture.move(to: CGPoint(x: p.x + 400, y: p.y))
        XCTAssertNil(gesture.end(at: p))
    }

    func testLongPunctuationSlidePreservesStartingKey() {
        let key = JoystickMapping.punctuation.first { $0.label == "." }!
        XCTAssertEqual(punctuationInput(key, dx: -400), .literal(","))
        XCTAssertEqual(punctuationInput(key, dy: -400), .literal("\""))
    }
    func testSecondBeginAndCancellation() {
        var gesture = AnchoredGesture()
        gesture.begin(pad: .c, at: start(.c,"ㅈ"), bounds: bounds)
        gesture.begin(pad: .c, at: start(.c,"ㄱ"), bounds: bounds)
        XCTAssertEqual(gesture.end(at: start(.c,"ㅈ")), .jamo("ㅈ"))
        gesture.begin(pad: .c, at: start(.c,"ㅈ"), bounds: bounds)
        gesture.cancel()
        XCTAssertNil(gesture.end(at: start(.c,"ㅈ")))
    }
    func testCircleGeometryAcrossSizesWithActiveCenterAndInactiveBoundaries() {
        for diameter: CGFloat in [140,180,240,280] {
            let rect = CGRect(x: 11,y: 17,width: diameter,height: diameter)
            for pad in [Pad.c,.v] {
                let centerLabel = pad == .c ? "ㅇ" : "ㅣ"
                XCTAssertEqual(JoystickMapping.centralKey(pad)?.label, centerLabel)
                XCTAssertEqual(JoystickMapping.ringKeys(pad).map(\.label), JoystickMapping.keys(pad).filter { $0.label != centerLabel }.map(\.label))
                for key in JoystickMapping.keys(pad) {
                    XCTAssertEqual(AnchoredGesture.symbol(pad: pad, at: start(pad,key.label,in:rect), bounds:rect),key.label)
                }
                XCTAssertEqual(start(pad, centerLabel, in: rect), CGPoint(x: rect.midX, y: rect.midY))
                XCTAssertEqual(AnchoredGesture.symbol(pad: pad, at: CGPoint(x:rect.midX,y:rect.midY), bounds:rect), centerLabel)
                XCTAssertEqual(AnchoredGesture.symbol(pad: pad, at: CGPoint(x: rect.midX, y: rect.midY - diameter * 0.19 + 0.5), bounds: rect), centerLabel)
                let radialGap = CGPoint(x: rect.midX, y: rect.midY - diameter * 0.19 - 2)
                XCTAssertNil(AnchoredGesture.symbol(pad: pad, at: radialGap, bounds: rect))
                XCTAssertNil(AnchoredGesture.symbol(pad: pad, at: rect.origin, bounds:rect))
                // Angular boundary between top and next key is inactive.
                let angle = -CGFloat.pi/2 + .pi / CGFloat(JoystickMapping.ringKeys(pad).count)
                let edge = CGPoint(x:rect.midX + cos(angle)*diameter*0.34, y:rect.midY + sin(angle)*diameter*0.34)
                XCTAssertNil(AnchoredGesture.symbol(pad: pad, at: edge, bounds:rect))
            }
        }
    }
    func testCenterAndRingSelectionInNonSquareBounds() {
        for rect in [CGRect(x: 11, y: 17, width: 280, height: 160), CGRect(x: 11, y: 17, width: 160, height: 280)] {
            for pad in [Pad.c, .v] {
                for key in JoystickMapping.keys(pad) {
                    XCTAssertEqual(JoystickMapping.key(pad: pad, at: start(pad, key.label, in: rect), bounds: rect)?.label, key.label)
                }
                XCTAssertNil(JoystickMapping.key(pad: pad, at: CGPoint(x: rect.minX + 1, y: rect.minY + 1), bounds: rect))
            }
        }
    }
    func testMovingFromCenterAcrossRingRetainsCenterGlyph() {
        XCTAssertEqual(input(.c, "ㅇ", dx: 82), .jamo("ㅎ"))
        XCTAssertEqual(input(.v, "ㅣ", dx: 82), .jamo("ㅏ"))
        // Reaching the active center from ㄱ must not switch to ㅇ.
        let point = start(.c, "ㄱ")
        var gesture = AnchoredGesture()
        gesture.begin(pad: .c, at: point, bounds: bounds)
        XCTAssertEqual(gesture.end(at: CGPoint(x: bounds.midX, y: bounds.midY)), .literal("5"))
    }
    func testOfficialPunctuationDirectionsProduceLiterals() {
        let expected: [(String, [Direction: String])] = [
            (".", [.tap: ".", .n: "\"", .w: ",", .s: "'", .e: "_"]),
            ("?", [.tap: "?", .n: "!", .w: "+", .s: "*", .e: "-"]),
            ("/", [.tap: "/", .n: ":", .w: "@", .s: ";", .e: "="])
        ]
        XCTAssertEqual(JoystickMapping.punctuation.map(\.label), expected.map { $0.0 })
        for (label, outputs) in expected {
            guard let key = JoystickMapping.punctuation.first(where: { $0.label == label }) else { XCTFail("Missing punctuation key \(label)"); continue }
            XCTAssertEqual(key.outputs, outputs)
            for (direction, dx, dy) in [(Direction.tap, 0.0, 0.0), (.n, 0, -30), (.s, 0, 30), (.w, -30, 0), (.e, 30, 0)] {
                XCTAssertEqual(key.action(direction), outputs[direction].map { .literal($0) })
                XCTAssertEqual(punctuationInput(key, dx: dx, dy: dy), outputs[direction].map { .literal($0) }, "\(label) \(direction)")
            }
        }
        for pad in [Pad.c, .v] {
            for key in JoystickMapping.keys(pad) {
                for (direction, value) in key.outputs {
                    let expected: KeyboardAction = HangulComposer.initials.contains(value) || HangulComposer.vowels.contains(value) ? .jamo(value) : .literal(value)
                    XCTAssertEqual(key.action(direction), expected)
                }
            }
        }
    }
    func testPunctuationCancellationAndStartingKeyOwnership() {
        let key = JoystickMapping.punctuation.first { $0.label == "." }!
        XCTAssertNil(punctuationInput(key, dx: 30, dy: 30))
        XCTAssertNil(punctuationInput(key, dx: 16))
        XCTAssertEqual(punctuationInput(key, dx: 400), .literal("_"))
        let rect = CGRect(x: 40, y: 50, width: 84, height: 44)
        let point = CGPoint(x: rect.midX, y: rect.midY)
        var gesture = AnchoredGesture()
        gesture.begin(key: key, at: point, bounds: rect)
        gesture.move(to: CGPoint(x: point.x - 30, y: point.y))
        XCTAssertNil(gesture.end(at: point))
        gesture.begin(key: key, at: point, bounds: rect)
        gesture.begin(key: JoystickMapping.punctuation.first { $0.label == "?" }!, at: point, bounds: rect)
        XCTAssertEqual(gesture.end(at: point), .literal("."))
        gesture.begin(key: key, at: point, bounds: rect)
        gesture.cancel()
        XCTAssertNil(gesture.end(at: point))
    }
    func testReversalForYaeAndYeFromBothVowelKeys() {
        for key in ["··", "ㅡ"] {
            let origin = start(.v, key)
            for (sign, vowel, initial) in [(CGFloat(1), "ㅒ", key == "··" ? "ㅑ" : "ㅐ"),
                                           (-1, "ㅖ", key == "··" ? "ㅕ" : "ㅔ")] {
                var gesture = AnchoredGesture()
                gesture.begin(pad: .v, at: origin, bounds: bounds)
                gesture.move(to: CGPoint(x: origin.x + sign * 35, y: origin.y))
                XCTAssertEqual(gesture.candidate, initial)
                gesture.move(to: CGPoint(x: origin.x + sign * 25, y: origin.y))
                XCTAssertNotEqual(gesture.candidate, vowel)
                gesture.move(to: CGPoint(x: origin.x + sign * 15, y: origin.y))
                XCTAssertEqual(gesture.candidate, vowel)
                XCTAssertEqual(gesture.preview.kind, .direction)
                XCTAssertEqual(gesture.end(at: origin), .jamo(vowel))

                gesture.begin(pad: .v, at: origin, bounds: bounds)
                gesture.move(to: CGPoint(x: origin.x + sign * 35, y: origin.y))
                gesture.move(to: CGPoint(x: origin.x - sign * 25, y: origin.y))
                XCTAssertEqual(gesture.end(at: CGPoint(x: origin.x - sign * 25, y: origin.y)), .jamo(vowel))

                gesture.begin(pad: .v, at: origin, bounds: bounds)
                gesture.move(to: CGPoint(x: origin.x + sign * 35, y: origin.y))
                gesture.cancel()
                XCTAssertNil(gesture.end(at: origin))
            }
        }
    }

    func testVerticalTurnsAndOtherKeysDoNotProduceCompoundVowels() {
        for key in ["··", "ㅡ", "ㅣ"] {
            let origin = start(.v, key)
            var gesture = AnchoredGesture()
            gesture.begin(pad: .v, at: origin, bounds: bounds)
            gesture.move(to: CGPoint(x: origin.x + 30, y: origin.y))
            gesture.move(to: CGPoint(x: origin.x + 30, y: origin.y - 25))
            XCTAssertNotEqual(gesture.candidate, "ㅒ")
            gesture.cancel()
        }
        let origin = start(.v, "ㅣ")
        var gesture = AnchoredGesture()
        gesture.begin(pad: .v, at: origin, bounds: bounds)
        gesture.move(to: CGPoint(x: origin.x + 30, y: origin.y))
        gesture.move(to: CGPoint(x: origin.x - 30, y: origin.y))
        XCTAssertNotEqual(gesture.candidate, "ㅒ")
    }

    func testVowelCompositionAndSingleDelete() {
        var model = ThreePadModel()
        for action in [input(.c,"ㅈ",dx:30)!, input(.v,"ㅣ",dx:30)!] { model.apply(action) }
        XCTAssertEqual(model.text,"차")
        model.apply(.delete); XCTAssertEqual(model.text,"ㅊ")
        model.apply(.delete); XCTAssertEqual(model.text,"")
        model.apply(input(.v,"··",dx:30)!); model.apply(input(.v,"ㅣ")!)
        XCTAssertEqual(model.text,"ㅒ")
        model.apply(.delete); XCTAssertEqual(model.text,"ㅑ")
        model.reset()
        model.apply(input(.v,"··",dx:-30)!); model.apply(input(.v,"ㅣ")!)
        XCTAssertEqual(model.text,"ㅖ")
    }
    func testAllModernSyllablesThroughAvailableGestures() {
        var paths: [String:[KeyboardAction]] = [:]
        for pad in [Pad.c,.v] {
            for key in JoystickMapping.keys(pad) {
                for (direction, value) in key.outputs {
                    let dx: CGFloat = direction == .e ? 30 : direction == .w ? -30 : 0
                    let dy: CGFloat = direction == .s ? 30 : direction == .n ? -30 : 0
                    paths[value] = [input(pad,key.label,dx:dx,dy:dy)!]
                }
            }
        }
        paths["ㅒ"] = paths["ㅑ"]! + paths["ㅣ"]!
        paths["ㅖ"] = paths["ㅕ"]! + paths["ㅣ"]!
        XCTAssertTrue((HangulComposer.initials + HangulComposer.vowels).allSatisfy { paths[$0] != nil })
        for scalar in 0xAC00...0xD7A3 {
            let syllable = String(UnicodeScalar(scalar)!)
            var model = ThreePadModel()
            for value in HangulComposer.decompose(syllable)! {
                for action in paths[value]! { XCTAssertTrue(model.apply(action)) }
            }
            XCTAssertEqual(model.text,syllable)
        }
    }
}
