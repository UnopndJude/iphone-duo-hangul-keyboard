import XCTest
@testable import ThreePadCore

final class ThreePadModelTests: XCTestCase {
    private func model(_ text: String) -> ThreePadModel {
        var model = ThreePadModel()
        for action in ThreePadMapping.encodeText(text) { XCTAssertTrue(model.apply(action)) }
        return model
    }

    func testAll11172ModernSyllablesRoundTrip() {
        for codepoint in 0xAC00...0xD7A3 {
            let expected = String(UnicodeScalar(codepoint)!)
            let actual = model(expected)
            XCTAssertEqual(actual.text, expected, "U+\(String(codepoint, radix: 16))")
        }
    }

    func testEveryModernJamoIsReachable() {
        let jamo = HangulComposer.initials + HangulComposer.vowels
        XCTAssertEqual(jamo.count, 40)
        for value in jamo {
            XCTAssertNotNil(ThreePadMapping.encodeJamo(value))
            XCTAssertEqual(model(value).text, value)
        }
    }

    func testWordsWithCompoundFinalsAndVowels() {
        for word in ["한글", "괜찮아", "뛰어", "값", "닭", "읽어", "앉아", "없어", "읊어", "넓어", "똑똑", "안녕하세요", "힣", "한글 | 🙂"] {
            XCTAssertEqual(model(word).text, word)
        }
    }

    func testSequentialVowelDeletionPreservesEarlierComponent() {
        var value = model("괘")
        XCTAssertEqual(value.target, "ㅙ")
        XCTAssertFalse(value.apply(.pad(.m, .n)))
        XCTAssertEqual(value.text, "괘")
        XCTAssertTrue(value.apply(.delete)); XCTAssertEqual(value.text, "고")
        XCTAssertTrue(value.apply(.delete)); XCTAssertEqual(value.text, "ㄱ")
        XCTAssertTrue(value.apply(.delete)); XCTAssertEqual(value.text, "")
        XCTAssertFalse(value.apply(.delete))
        var direct = model("ㅢ")
        direct.apply(.delete); XCTAssertEqual(direct.text, "")
        var sequential = ThreePadModel()
        sequential.apply(.pad(.v, .se)); sequential.apply(.pad(.v, .tap))
        XCTAssertEqual(sequential.text, "ㅢ")
        sequential.apply(.delete); XCTAssertEqual(sequential.text, "ㅡ")
    }

    func testDeletionReplaysFinalSplitting() {
        var value = model("갑사")
        for expected in ["값", "갑", "가", "ㄱ", ""] {
            XCTAssertTrue(value.apply(.delete)); XCTAssertEqual(value.text, expected)
        }
        value = model("읽어")
        for expected in ["읽ㅇ", "읽", "일", "이", "ㅇ", ""] {
            XCTAssertTrue(value.apply(.delete)); XCTAssertEqual(value.text, expected)
        }
    }

    func testModifierCanRecombineFinalAndUndoIt() {
        var value = model("찬ㅇ")
        XCTAssertTrue(value.apply(.pad(.m, .n))); XCTAssertEqual(value.text, "찮")
        XCTAssertTrue(value.canUndoModifier)
        XCTAssertTrue(value.apply(.pad(.m, .tap))); XCTAssertEqual(value.text, "찬ㅇ")
        XCTAssertFalse(value.canUndoModifier)
        XCTAssertFalse(value.apply(.pad(.m, .tap)))
        value = model("ㅋ")
        value.apply(.delete); XCTAssertEqual(value.text, "")
    }

    func testModifiersStopAtLiteralBoundaryAndExpireAfterNewInput() {
        for boundary in [" ", "\n", ".", "|", "🙂"] {
            var value = model("ㅋ")
            XCTAssertTrue(value.canUndoModifier)
            XCTAssertTrue(value.apply(.literal(boundary)))
            XCTAssertNil(value.target)
            XCTAssertFalse(value.canUndoModifier)
            XCTAssertFalse(value.apply(.pad(.m, .n)))
            XCTAssertFalse(value.apply(.pad(.m, .s)))
            XCTAssertFalse(value.apply(.pad(.m, .tap)))
            XCTAssertEqual(value.text, "ㅋ" + boundary)
            value.apply(.pad(.v, .e)); XCTAssertEqual(value.text, "ㅋ" + boundary + "ㅏ")
        }
        var value = model("카")
        XCTAssertFalse(value.canUndoModifier)
        XCTAssertFalse(value.apply(.pad(.m, .tap)))
    }

    func testInvalidModifiersAreNoOpWithoutExpiringValidUndo() {
        var value = model("ㅋ")
        XCTAssertTrue(value.canUndoModifier)
        XCTAssertFalse(value.apply(.pad(.m, .s)))
        XCTAssertFalse(value.apply(.pad(.m, .e)))
        XCTAssertTrue(value.canUndoModifier)
        XCTAssertTrue(value.apply(.pad(.m, .tap))); XCTAssertEqual(value.text, "ㄱ")
    }

    func testHistoryRestoresModifierStateAndClearsRedoOnBranch() {
        var value = model("ㅋ")
        value.apply(.pad(.m, .tap)); XCTAssertEqual(value.text, "ㄱ")
        value.apply(.undo); XCTAssertEqual(value.text, "ㅋ"); XCTAssertTrue(value.canUndoModifier)
        value.apply(.redo); XCTAssertEqual(value.text, "ㄱ"); XCTAssertFalse(value.canUndoModifier)
        value.apply(.undo); value.apply(.pad(.v, .e))
        XCTAssertEqual(value.text, "카"); XCTAssertFalse(value.canRedo)
        value.apply(.clear); XCTAssertEqual(value.text, "")
        value.apply(.undo); XCTAssertEqual(value.text, "카")
        value.reset()
        XCTAssertEqual(value.text, ""); XCTAssertNil(value.target)
        XCTAssertFalse(value.canUndo); XCTAssertFalse(value.canRedo); XCTAssertFalse(value.canUndoModifier)
    }

    func testHistoryHasBounded180Edits() {
        var value = ThreePadModel()
        for _ in 0..<200 { value.apply(.literal("a")) }
        var count = 0
        while value.apply(.undo) { count += 1 }
        XCTAssertEqual(count, 180)
        XCTAssertEqual(value.text, String(repeating: "a", count: 20))
        count = 0
        while value.apply(.redo) { count += 1 }
        XCTAssertEqual(count, 180)
        XCTAssertEqual(value.text.count, 200)
    }

    func testLiteralIsOneGraphemeAndNeverFeedsComposition() {
        var value = ThreePadModel()
        XCTAssertFalse(value.apply(.literal("")))
        XCTAssertFalse(value.apply(.literal("abc")))
        XCTAssertFalse(value.canUndo)
        XCTAssertTrue(value.apply(.literal("👨‍👩‍👧‍👦")))
        value.apply(.delete); XCTAssertEqual(value.text, "")
        value.apply(.pad(.c, .n)); value.apply(.literal("ㅏ"))
        XCTAssertEqual(value.text, "ㄱㅏ")
        XCTAssertNil(value.target)
    }

    func testCommitPreservesTextButPreventsRecompositionAcrossLanguageSwitch() {
        var value = model("간")
        XCTAssertTrue(value.apply(.commit))
        XCTAssertEqual(value.text, "간"); XCTAssertNil(value.target)
        XCTAssertTrue(value.apply(.jamo("ㅏ")))
        XCTAssertEqual(value.text, "간ㅏ")
        XCTAssertTrue(value.apply(.delete)); XCTAssertEqual(value.text, "간")
        XCTAssertTrue(value.apply(.delete)); XCTAssertEqual(value.text, "")
    }

    func testCommitIsUndoBoundaryWithoutLosingTextOrRestoringOldJamo() {
        var value = model("ㅋ")
        XCTAssertTrue(value.canUndoModifier)
        value.apply(.jamo("ㅏ")); value.apply(.undo)
        XCTAssertTrue(value.canRedo)
        XCTAssertTrue(value.apply(.commit))
        XCTAssertEqual(value.text, "ㅋ")
        XCTAssertFalse(value.canUndoModifier); XCTAssertFalse(value.canUndo); XCTAssertFalse(value.canRedo)
        XCTAssertFalse(value.apply(.undo)); XCTAssertFalse(value.apply(.redo))
        XCTAssertFalse(value.apply(.pad(.m, .tap)))
        value.apply(.literal("a")); value.apply(.undo)
        XCTAssertEqual(value.text, "ㅋ"); XCTAssertNil(value.target)
        XCTAssertFalse(value.apply(.undo))
        value.apply(.redo); XCTAssertEqual(value.text, "ㅋa")
        value.apply(.delete); XCTAssertEqual(value.text, "ㅋ")
    }

    func testRepeatedAndEmptyCommitPreserveDisplayedCharacters() {
        var value = ThreePadModel()
        XCTAssertTrue(value.apply(.commit)); XCTAssertEqual(value.text, "")
        value = model("한🙂 | ㄱ")
        let before = value.text
        XCTAssertTrue(value.apply(.commit)); XCTAssertTrue(value.apply(.commit))
        XCTAssertEqual(value.text, before)
        value.apply(.jamo("ㅏ"))
        XCTAssertEqual(value.text, before + "ㅏ")
    }

    func testEnglishDeletionAfterCommitPreservesPreviousHangul() throws {
        var value = model("간")
        var keyboard = EnglishKeyboard()
        value.apply(.commit)
        value.apply(try XCTUnwrap(keyboard.input("a")))
        keyboard.toggleShift()
        value.apply(try XCTUnwrap(keyboard.input("b")))
        XCTAssertEqual(value.text, "간aB")
        value.apply(.delete); XCTAssertEqual(value.text, "간a")
        value.apply(.delete); XCTAssertEqual(value.text, "간")
        value.apply(.jamo("ㅏ")); XCTAssertEqual(value.text, "간ㅏ")
    }
}
