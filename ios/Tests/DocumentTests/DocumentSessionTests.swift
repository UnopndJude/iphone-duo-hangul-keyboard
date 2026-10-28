import XCTest
import ThreePadCore
@testable import ThreePadDocument

private final class TestDocument: KeyboardDocument {
    var identifier = UUID()
    var text = ""
    var cursor = 0
    var selectionLength = 0
    var mark: Range<Int>?
    var deleteCalls = 0
    var insertCalls = 0
    var cursorOffsets: [Int] = []
    var unmarkCalls = 0
    var markedRanges: [NSRange] = []
    var hidesContext = false
    var defersUnmark = false
    var normalizesMarkedNewlines = false
    var onWrite: (() -> Void)?
    var before: String? { hidesContext ? nil : String(Array(text).prefix(cursor)) }
    var after: String? { hidesContext ? nil : String(Array(text).dropFirst(cursor + selectionLength)) }
    var selected: String? { selectionLength == 0 ? nil : String(Array(text).dropFirst(cursor).prefix(selectionLength)) }

    func setMarkedText(_ value: String, selectedRange: NSRange) {
        var chars = Array(text)
        let range = mark ?? cursor..<(cursor + selectionLength)
        chars.replaceSubrange(range, with: Array(value))
        text = String(chars)
        mark = range.lowerBound..<(range.lowerBound + value.count)
        cursor = range.lowerBound + value.count
        selectionLength = 0
        markedRanges.append(selectedRange)
        onWrite?()
    }
    func unmarkText() {
        unmarkCalls += 1
        if !defersUnmark { mark = nil }
        onWrite?()
    }
    func insertText(_ value: String) {
        insertCalls += 1
        var chars = Array(text)
        let range = mark ?? cursor..<(cursor + selectionLength)
        let inserted = normalizesMarkedNewlines && mark != nil ? value.replacingOccurrences(of: "\n", with: " ") : value
        chars.replaceSubrange(range, with: Array(inserted))
        text = String(chars); cursor = range.lowerBound + inserted.count
        selectionLength = 0; mark = nil; onWrite?()
    }
    func adjustTextPosition(byCharacterOffset offset: Int) {
        cursorOffsets.append(offset)
        let start = String(text.prefix(cursor)).utf16.count
        let target = max(0, min(text.utf16.count, start + offset))
        var length = 0
        cursor = 0
        for character in text {
            let next = length + String(character).utf16.count
            guard next <= target else { break }
            length = next; cursor += 1
        }
        selectionLength = 0; mark = nil; onWrite?()
    }
    func deleteBackward() {
        deleteCalls += 1
        var chars = Array(text)
        if selectionLength > 0 { chars.removeSubrange(cursor..<(cursor + selectionLength)); selectionLength = 0 }
        else if cursor > 0 { chars.remove(at: cursor - 1); cursor -= 1 }
        text = String(chars); mark = nil; onWrite?()
    }
}

final class DocumentSessionTests: XCTestCase {
    private func input(_ actions: [KeyboardAction], _ session: DocumentSession, _ doc: TestDocument) {
        for action in actions { XCTAssertTrue(session.apply(action, to: doc)) }
    }
    private let ga: [KeyboardAction] = [.pad(.c,.n), .pad(.v,.e)]

    func testCompositionUsesMarkedTextWithoutDeletingExistingDocument() {
        let d = TestDocument(), s = DocumentSession()
        d.text = "앞 "; d.cursor = 2
        input(ga, s, d)
        XCTAssertEqual(d.text, "앞 가"); XCTAssertEqual(d.deleteCalls, 0)
        XCTAssertEqual(d.mark, 2..<3)
        XCTAssertEqual(d.markedRanges.last, NSRange(location: 1, length: 0))
    }

    func testModifierCompoundDeletionAndBoundary() {
        let d = TestDocument(), s = DocumentSession()
        input([.pad(.c,.n),.pad(.v,.n),.pad(.v,.ne)], s, d)
        XCTAssertEqual(d.text, "괘")
        input([.delete], s, d); XCTAssertEqual(d.text, "고")
        input([.literal(" ")], s, d)
        XCTAssertNil(d.mark); XCTAssertEqual(s.composition, "")
        XCTAssertFalse(s.apply(.pad(.m,.n), to: d)); XCTAssertEqual(d.text, "고 ")
        input([.delete], s, d); XCTAssertEqual(d.text, "고"); XCTAssertEqual(d.deleteCalls, 1)
    }

    func testCursorMoveCommitsAndNeverRewritesOldMarkedText() {
        let d = TestDocument(), s = DocumentSession()
        input(ga, s, d); s.finish(in: d)
        d.cursor = 0
        input([.pad(.c,.tap)], s, d)
        XCTAssertEqual(d.text, "ㅇ가"); XCTAssertEqual(d.mark, 0..<1)
    }

    func testExternalTextAndDocumentChangeInvalidateComposition() {
        let d = TestDocument(), s = DocumentSession()
        input(ga, s, d)
        d.text = "바뀜"; d.cursor = 2; d.mark = nil
        XCTAssertTrue(s.synchronize(with: d))
        XCTAssertNil(s.target)
        input([.pad(.c,.tap)], s, d); XCTAssertEqual(d.text, "바뀜ㅇ")
        d.identifier = UUID(); d.text = "새 문서"; d.cursor = 4; d.mark = nil
        input([.pad(.c,.n)], s, d); XCTAssertEqual(d.text, "새 문서ㄱ")
    }

    func testSelectionReplacementAndDeleteRespectHostSelection() {
        let d = TestDocument(), s = DocumentSession()
        d.text = "앞 뒤"; d.cursor = 2; d.selectionLength = 1
        input(ga, s, d); XCTAssertEqual(d.text, "앞 가")
        s.finish(in: d); d.cursor = 0; d.selectionLength = 2
        input([.delete], s, d); XCTAssertEqual(d.text, "가")
    }

    func testNewDocumentMarkedTextIsNotUnmarkedByOldSession() {
        let old = TestDocument(), new = TestDocument(), s = DocumentSession()
        input(ga, s, old)
        new.text = "독립"; new.cursor = 2; new.mark = 0..<2
        XCTAssertTrue(s.synchronize(with: new))
        XCTAssertEqual(new.unmarkCalls, 0); XCTAssertEqual(new.mark, 0..<2)
        XCTAssertNil(s.target)
        // Disappearance is also harmless if the proxy has already switched.
        input(ga, s, old)
        s.finish(in: new)
        XCTAssertEqual(new.unmarkCalls, 0)
    }

    func testOwnSynchronousAndDeferredCallbacksPreserveComposition() {
        let d = TestDocument(), s = DocumentSession()
        d.onWrite = { XCTAssertFalse(s.synchronize(with: d)); s.finish(in: d) }
        input(ga, s, d)
        XCTAssertFalse(s.synchronize(with: d))
        XCTAssertEqual(s.composition, "가")
        input([.pad(.c,.ne)], s, d); XCTAssertEqual(d.text, "간")
    }

    func testSynchronizeReportsCursorSelectionAndDocumentChangesOnlyOnce() {
        let d = TestDocument(), s = DocumentSession()
        XCTAssertFalse(s.synchronize(with: d))
        input(ga, s, d)
        XCTAssertFalse(s.synchronize(with: d))
        d.cursor = 0; d.mark = nil
        XCTAssertTrue(s.synchronize(with: d))
        XCTAssertEqual(s.composition, "")
        XCTAssertFalse(s.synchronize(with: d))
        d.selectionLength = 1
        XCTAssertTrue(s.synchronize(with: d))
        XCTAssertFalse(s.synchronize(with: d))
        d.identifier = UUID()
        XCTAssertTrue(s.synchronize(with: d))
        XCTAssertFalse(s.synchronize(with: d))
    }

    func testMissingContextUsesMarkedAPIAndNoDeleteLoop() {
        let d = TestDocument(), s = DocumentSession(); d.hidesContext = true
        input(ga, s, d)
        XCTAssertEqual(d.text, "가"); XCTAssertEqual(d.deleteCalls, 0)
        s.finish(in: d); XCTAssertNil(d.mark)
    }

    func testDeletingAllCompositionRemovesMarkAndDoesNotDeletePrefix() {
        let d = TestDocument(), s = DocumentSession(); d.text = "기존"; d.cursor = 2
        input(ga + [.delete,.delete], s, d)
        XCTAssertEqual(d.text, "기존"); XCTAssertNil(d.mark); XCTAssertEqual(d.deleteCalls, 0)
    }

    func testLongUnbrokenInputPreservesComposition() {
        let d = TestDocument(), s = DocumentSession()
        input(Array(repeating: .pad(.c,.n), count: 130), s, d)
        XCTAssertEqual(d.text.count, 130); XCTAssertEqual(s.composition.count, 130)
    }

    func testCompoundVowelAcrossFormerLengthBoundary() {
        let d = TestDocument(), s = DocumentSession()
        input(Array(repeating: .pad(.c,.tap), count: 62), s, d)
        input([.pad(.c,.n),.pad(.v,.n),.pad(.v,.e)], s, d)
        XCTAssertTrue(d.text.hasSuffix("과"))
        XCTAssertFalse(d.text.hasSuffix("고ㅏ"))
    }

    func testInvalidLiteralDoesNotCommitAndFinishIsIdempotent() {
        let d = TestDocument(), s = DocumentSession()
        input(ga, s, d)
        XCTAssertFalse(s.apply(.literal("abc"), to: d)); XCTAssertEqual(s.composition, "가")
        s.finish(in: d); s.finish(in: d); XCTAssertEqual(d.text, "가"); XCTAssertNil(d.mark)
    }

    func testQuickPunctuationCommitsCompositionAndDeletesOnlyPunctuation() {
        for key in JoystickMapping.punctuation {
            for (direction, value) in key.outputs {
                let d = TestDocument(), s = DocumentSession()
                d.text = "앞 "; d.cursor = 2
                input([.jamo("ㅎ"), .jamo("ㅏ"), .jamo("ㄴ")], s, d)
                XCTAssertEqual(d.text, "앞 한")
                XCTAssertEqual(d.mark, 2..<3)
                guard let action = key.action(direction) else { XCTFail("Missing action for \(key.label) \(direction)"); continue }
                XCTAssertEqual(action, .literal(value))
                input([action], s, d)
                XCTAssertEqual(d.text, "앞 한" + value)
                XCTAssertNil(d.mark)
                XCTAssertEqual(s.composition, "")
                XCTAssertEqual(d.insertCalls, 1)
                XCTAssertEqual(d.unmarkCalls, 0)
                input([.delete], s, d)
                XCTAssertEqual(d.text, "앞 한")
                XCTAssertEqual(d.deleteCalls, 1)
                XCTAssertEqual(s.composition, "")
                // The committed syllable is now owned by the document, not local jamo history.
                input([.delete], s, d)
                XCTAssertEqual(d.text, "앞 ")
                XCTAssertEqual(d.deleteCalls, 2)
            }
        }
    }

    func testEveryPaletteSymbolPreservesHangulAndDeletesAsOneCharacter() {
        for symbol in SymbolKeyboard.pages.flatMap({ $0 }) {
            let d = TestDocument(), s = DocumentSession()
            input([.jamo("ㅎ"), .jamo("ㅏ"), .jamo("ㄴ"), .commit, .literal(symbol)], s, d)
            XCTAssertEqual(d.text, "한" + symbol, symbol)
            XCTAssertNil(d.mark, symbol)
            input([.delete], s, d)
            XCTAssertEqual(d.text, "한", symbol)
            input([.jamo("ㅏ")], s, d)
            XCTAssertEqual(d.text, "한ㅏ", symbol)
        }
    }

    func testPunctuationSeparatesConsecutiveHangulCompositions() {
        let d = TestDocument(), s = DocumentSession()
        let period = JoystickMapping.punctuation.first { $0.label == "." }!
        input([.jamo("ㄱ"), .jamo("ㅏ"), .jamo("ㄴ"), period.action(.tap)!, .jamo("ㅏ")], s, d)
        XCTAssertEqual(d.text, "간.ㅏ")
        XCTAssertEqual(s.composition, "ㅏ")
        XCTAssertEqual(d.mark, 2..<3)
        input([.delete], s, d)
        XCTAssertEqual(d.text, "간.")
        XCTAssertNil(d.mark)
        XCTAssertEqual(d.deleteCalls, 0)
        input([.delete], s, d)
        XCTAssertEqual(d.text, "간")
        XCTAssertEqual(d.deleteCalls, 1)
    }

    func testTildeAndDigitsCommitHangulAndDeleteAsLiterals() throws {
        let tildeKey = try XCTUnwrap(JoystickMapping.consonants.first { $0.label == "ㅈ" })
        let tilde = try XCTUnwrap(tildeKey.action(.s))
        XCTAssertEqual(tilde, .literal("~"))
        // Exercise the tilde action and the literal actions used by the 123 palette.
        for suffix in ["~", "0123456789~"] {
            let d = TestDocument(), s = DocumentSession()
            input([.jamo("ㅎ"), .jamo("ㅏ"), .jamo("ㄴ")], s, d)
            input(suffix.map { $0 == "~" ? tilde : .literal(String($0)) }, s, d)
            XCTAssertEqual(d.text, "한" + suffix)
            XCTAssertNil(d.mark)
            XCTAssertEqual(s.composition, "")
            input([.jamo("ㅏ")], s, d)
            XCTAssertEqual(d.text, "한" + suffix + "ㅏ")
            input([.delete], s, d)
            XCTAssertEqual(d.text, "한" + suffix)
            XCTAssertEqual(d.deleteCalls, 0)
            var remaining = suffix
            while !remaining.isEmpty {
                remaining.removeLast()
                input([.delete], s, d)
                XCTAssertEqual(d.text, "한" + remaining)
            }
            XCTAssertEqual(d.deleteCalls, suffix.count)
            input([.delete], s, d)
            XCTAssertEqual(d.text, "")
        }
    }

    func testLanguageSwitchCommitsWithoutInsertingTextAndPreventsRecomposition() {
        let d = TestDocument(), s = DocumentSession()
        input([.jamo("ㄱ"), .jamo("ㅏ"), .jamo("ㄴ")], s, d)
        XCTAssertEqual(d.text, "간")
        let writes = d.markedRanges.count
        input([.commit], s, d)
        XCTAssertEqual(d.text, "간"); XCTAssertNil(d.mark)
        XCTAssertEqual(s.composition, ""); XCTAssertNil(s.target)
        XCTAssertEqual(d.insertCalls, 0); XCTAssertEqual(d.deleteCalls, 0)
        XCTAssertEqual(d.markedRanges.count, writes); XCTAssertEqual(d.unmarkCalls, 1)
        input([.commit], s, d)
        XCTAssertEqual(d.unmarkCalls, 1)
        input([.jamo("ㅏ")], s, d)
        XCTAssertEqual(d.text, "간ㅏ")
        XCTAssertEqual(d.mark, 1..<2)
    }

    func testEnglishTypingAndDeletionPreservePreviouslyCommittedHangul() throws {
        let d = TestDocument(), s = DocumentSession()
        var keyboard = EnglishKeyboard()
        d.text = "앞 "; d.cursor = 2
        input([.jamo("ㄱ"), .jamo("ㅏ"), .jamo("ㄴ"), .commit], s, d)
        let first = try XCTUnwrap(keyboard.input("a"))
        keyboard.toggleShift()
        let second = try XCTUnwrap(keyboard.input("b"))
        input([first, second], s, d)
        XCTAssertEqual(d.text, "앞 간aB"); XCTAssertNil(d.mark)
        input([.delete], s, d); XCTAssertEqual(d.text, "앞 간a")
        input([.delete], s, d); XCTAssertEqual(d.text, "앞 간")
        XCTAssertEqual(d.deleteCalls, 2)
        input([.commit, .jamo("ㅏ")], s, d)
        XCTAssertEqual(d.text, "앞 간ㅏ")
        input([.delete], s, d); XCTAssertEqual(d.text, "앞 간")
        XCTAssertEqual(d.deleteCalls, 2)
    }

    func testSpacePreservesCompositionWhenHostHasNotClearedMarkedRange() {
        let d = TestDocument(), s = DocumentSession()
        d.text = "앞 뒤"; d.cursor = 2; d.defersUnmark = true
        input([.jamo("ㅎ"), .jamo("ㅏ"), .jamo("ㄴ"),
               .jamo("ㄱ"), .jamo("ㅡ"), .jamo("ㄹ")], s, d)
        XCTAssertEqual(d.text, "앞 한글뒤")
        input([.literal(" ")], s, d)
        XCTAssertEqual(d.text, "앞 한글 뒤")
        XCTAssertEqual(d.insertCalls, 1)
        XCTAssertEqual(d.unmarkCalls, 0)
        XCTAssertNil(d.mark)
        XCTAssertEqual(s.composition, "")
        input([.literal(" "), .jamo("ㄱ"), .jamo("ㅏ"), .literal(" ")], s, d)
        XCTAssertEqual(d.text, "앞 한글  가 뒤")
        input([.delete], s, d)
        XCTAssertEqual(d.text, "앞 한글  가뒤")
        XCTAssertEqual(d.deleteCalls, 1)
    }

    func testLiteralBoundariesCommitOneReplacementWithReentrantCallbacks() {
        for literal in [" ", "\n", ".", "~", "1", "a"] {
            let d = TestDocument(), s = DocumentSession()
            d.defersUnmark = true
            d.onWrite = { XCTAssertFalse(s.synchronize(with: d)); s.finish(in: d) }
            input(ga + [.literal(literal)], s, d)
            XCTAssertEqual(d.text, "가" + literal)
            XCTAssertEqual(d.insertCalls, literal == "\n" ? 2 : 1)
            XCTAssertNil(d.mark)
            XCTAssertEqual(s.composition, "")
            XCTAssertFalse(s.synchronize(with: d))
        }
    }
    func testFirstReturnAfterHangulIsStandaloneNewline() {
        let d = TestDocument(), s = DocumentSession()
        d.normalizesMarkedNewlines = true
        input(ga + [.literal("\n"), .literal("\n"), .jamo("ㄴ"), .jamo("ㅏ")], s, d)
        XCTAssertEqual(d.text, "가\n\n나")
        XCTAssertEqual(d.insertCalls, 3)
        XCTAssertEqual(d.unmarkCalls, 0)
    }

    func testBlockDeletePreservesEarlierWordsAndSelection() {
        let d = TestDocument(), s = DocumentSession()
        d.text = "앞 한글  "; d.cursor = d.text.count
        input([.deleteBlock], s, d)
        XCTAssertEqual(d.text, "앞 ")
        d.text = "앞 👨‍👩‍👧‍👦 뒤"; d.cursor = 2; d.selectionLength = 1
        input([.deleteBlock], s, d)
        XCTAssertEqual(d.text, "앞  뒤")
        XCTAssertEqual(d.deleteCalls, 5)
    }

    func testBlockDeleteBoundsAndMissingContext() {
        let d = TestDocument(), s = DocumentSession()
        d.text = String(repeating: "가", count: 80); d.cursor = 80
        input([.deleteBlock], s, d)
        XCTAssertEqual(d.text.count, 48)
        d.hidesContext = true
        input([.deleteBlock], s, d)
        XCTAssertEqual(d.text.count, 47)
        d.hidesContext = false
        d.text += "\n"; d.cursor = d.text.count
        input([.deleteBlock], s, d)
        XCTAssertEqual(d.text.count, 47)
    }

    func testBlockDeleteDuringCompositionDoesNotDeleteExistingPrefix() {
        let d = TestDocument(), s = DocumentSession()
        d.text = "앞 "; d.cursor = 2
        input(ga + [.deleteBlock], s, d)
        XCTAssertEqual(d.text, "앞 ")
        XCTAssertNil(d.mark)
        XCTAssertEqual(d.deleteCalls, 0)
        input([.deleteBlock], s, d)
        XCTAssertEqual(d.text, "")
        XCTAssertFalse(s.apply(.deleteBlock, to: d))
    }

    func testCursorSlideCommitsHangulWithoutSpaceAndInsertsAtNewPosition() {
        let d = TestDocument(), s = DocumentSession()
        input(ga + [.jamo("ㄴ"), .jamo("ㅏ")], s, d)
        XCTAssertEqual(d.text, "가나")
        s.moveCursor(by: -1, in: d)
        XCTAssertEqual(d.text, "가나")
        XCTAssertEqual(d.cursor, 1)
        XCTAssertNil(d.mark)
        XCTAssertEqual(s.composition, "")
        input([.literal("!")], s, d)
        XCTAssertEqual(d.text, "가!나")
        s.moveCursor(by: 1, in: d)
        XCTAssertEqual(d.cursor, 3)
    }

    func testCursorSlideCrossesWholeEmojiAndStopsAtDocumentEdges() {
        let d = TestDocument(), s = DocumentSession()
        d.text = "가👨‍👩‍👧‍👦é나"; d.cursor = d.text.count
        s.moveCursor(by: -2, in: d)
        XCTAssertEqual(d.cursor, 2)
        s.moveCursor(by: -1, in: d)
        XCTAssertEqual(d.cursor, 1)
        XCTAssertEqual(d.cursorOffsets.last, -"👨‍👩‍👧‍👦".utf16.count)
        s.moveCursor(by: -32, in: d)
        XCTAssertEqual(d.cursor, 0)
        s.moveCursor(by: 32, in: d)
        XCTAssertEqual(d.cursor, d.text.count)
        XCTAssertEqual(d.insertCalls, 0)
        XCTAssertEqual(d.deleteCalls, 0)
    }

    func testCursorSlideCallbacksAndUnknownContextAreBounded() {
        let d = TestDocument(), s = DocumentSession()
        input(ga, s, d)
        d.onWrite = { XCTAssertFalse(s.synchronize(with: d)) }
        s.moveCursor(by: -1, in: d)
        XCTAssertFalse(s.synchronize(with: d))
        d.hidesContext = true
        s.moveCursor(by: 30, in: d)
        XCTAssertEqual(d.cursorOffsets.last, 1)
    }
    func testEachConsonantDigitCommitsHangulAndDeletesAsLiteral() {
        let digits = JoystickMapping.consonants.flatMap { key in
            key.outputs.compactMap { direction, value in
                value.allSatisfy(\.isNumber) ? key.action(direction) : nil
            }
        }
        XCTAssertEqual(digits.count, 10)
        for digit in digits {
            let d = TestDocument(), s = DocumentSession()
            input([.jamo("ㅎ"), .jamo("ㅏ"), .jamo("ㄴ"), digit], s, d)
            guard case let .literal(value) = digit else { XCTFail(); continue }
            XCTAssertEqual(d.text, "한" + value)
            XCTAssertNil(d.mark)
            input([.delete, .jamo("ㄱ"), .jamo("ㅏ")], s, d)
            XCTAssertEqual(d.text, "한가")
        }
    }

    func testAllModernVowelsThroughActualJoystickActions() {
        var paths: [String: [KeyboardAction]] = [:]
        for key in JoystickMapping.vowels {
            for (direction, value) in key.outputs {
                if let action = key.action(direction) { paths[value] = [action] }
            }
        }
        paths["ㅒ"] = paths["ㅑ"]! + paths["ㅣ"]!
        paths["ㅖ"] = paths["ㅕ"]! + paths["ㅣ"]!
        XCTAssertEqual(Set(paths.keys), Set(HangulComposer.vowels))
        for vowel in HangulComposer.vowels {
            let d = TestDocument(), s = DocumentSession()
            let expected = HangulComposer.syllable("ㄱ", vowel)
            input([.jamo("ㄱ")] + paths[vowel]!, s, d)
            XCTAssertEqual(d.text, expected, vowel)
            input([.literal(" ")], s, d)
            XCTAssertEqual(d.text, expected + " ", vowel)
        }
    }

    func testYaAndYeoThenCenterProduceYaeAndYeAndDeleteLastComponent() {
        let pad = JoystickMapping.vowels.first { $0.label == "··" }!
        let center = JoystickMapping.vowels.first { $0.label == "ㅣ" }!
        for (direction, expected, previous) in [(Direction.e, "걔", "갸"), (.w, "계", "겨")] {
            let d = TestDocument(), s = DocumentSession()
            input([.jamo("ㄱ"), pad.action(direction)!, center.action(.tap)!], s, d)
            XCTAssertEqual(d.text, expected)
            input([.delete], s, d)
            XCTAssertEqual(d.text, previous)
        }
    }


}
