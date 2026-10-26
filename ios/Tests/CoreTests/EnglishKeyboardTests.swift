import XCTest
@testable import ThreePadCore

final class EnglishKeyboardTests: XCTestCase {
    func testQWERTYContainsEveryASCIIEnglishLetterOnce() {
        XCTAssertEqual(EnglishKeyboard.rows.map { $0.joined() }, ["qwertyuiop", "asdfghjkl", "zxcvbnm"])
        let letters = EnglishKeyboard.rows.flatMap { $0 }
        XCTAssertEqual(letters.count, 26)
        XCTAssertEqual(Set(letters), Set("abcdefghijklmnopqrstuvwxyz".map(String.init)))
        var keyboard = EnglishKeyboard()
        for letter in letters { XCTAssertEqual(keyboard.input(letter), .literal(letter)) }
        XCTAssertEqual(keyboard.letterCase, .lower)
    }

    func testShiftAppliesToExactlyOneSuccessfulLetter() {
        var keyboard = EnglishKeyboard()
        keyboard.toggleShift()
        XCTAssertEqual(keyboard.letterCase, .upper)
        XCTAssertEqual(keyboard.input("q"), .literal("Q"))
        XCTAssertEqual(keyboard.letterCase, .lower)
        XCTAssertEqual(keyboard.input("w"), .literal("w"))
        keyboard.toggleShift(); keyboard.toggleShift()
        XCTAssertEqual(keyboard.letterCase, .lower)
    }

    func testCapsLockPersistsAcrossEveryLetterUntilToggledOff() {
        var keyboard = EnglishKeyboard()
        keyboard.toggleCapsLock()
        for letter in EnglishKeyboard.rows.flatMap({ $0 }) {
            XCTAssertEqual(keyboard.input(letter), .literal(letter.uppercased()))
            XCTAssertEqual(keyboard.letterCase, .locked)
        }
        keyboard.toggleCapsLock()
        XCTAssertEqual(keyboard.input("a"), .literal("a"))
        keyboard.toggleShift(); keyboard.toggleCapsLock()
        XCTAssertEqual(keyboard.letterCase, .locked)
        keyboard.toggleShift()
        XCTAssertEqual(keyboard.letterCase, .lower)
    }

    func testInvalidInputDoesNotConsumeShiftOrProduceAnAction() {
        var keyboard = EnglishKeyboard()
        keyboard.toggleShift()
        for invalid in ["", "aa", "Q", "1", " ", "\n", ".", "한", "é", "e\u{301}", "ａ", "🙂"] {
            XCTAssertNil(keyboard.input(invalid), invalid)
            XCTAssertEqual(keyboard.letterCase, .upper)
        }
        XCTAssertEqual(keyboard.input("z"), .literal("Z"))
        XCTAssertEqual(keyboard.letterCase, .lower)
    }

    func testResetClearsBothCapitalModes() {
        var keyboard = EnglishKeyboard()
        keyboard.toggleShift(); keyboard.resetShift()
        XCTAssertEqual(keyboard.letterCase, .lower)
        keyboard.toggleCapsLock(); keyboard.resetShift()
        XCTAssertEqual(keyboard.letterCase, .lower)
    }
}
