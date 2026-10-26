import XCTest
import CoreGraphics
@testable import ThreePadCore

final class SymbolLayoutTests: XCTestCase {
    private let symbolIDs = (0..<28).map { "symbol-\($0)" }

    func testFixedPagesCoverDigitsAndEveryASCIIPunctuationWithoutDuplicates() {
        XCTAssertEqual(SymbolKeyboard.pages.count, 2)
        XCTAssertEqual(SymbolKeyboard.pageTitles.count, 2)
        for page in SymbolKeyboard.pages { XCTAssertEqual(page.count, 28) }
        let all = SymbolKeyboard.pages.flatMap { $0 }
        XCTAssertEqual(Set(all).count, 56)
        let ascii = (33...126).compactMap(UnicodeScalar.init).filter {
            (33...47).contains($0.value) || (58...64).contains($0.value)
                || (91...96).contains($0.value) || (123...126).contains($0.value)
        }.map(String.init)
        XCTAssertEqual(ascii.count, 32)
        XCTAssertTrue(Set(ascii + (0...9).map(String.init)).isSubset(of: Set(all)))
        XCTAssertEqual(Array(SymbolKeyboard.pages[0].prefix(10)), Array("1234567890").map(String.init))
        XCTAssertTrue(SymbolKeyboard.pages[0].contains("~"))
        for symbol in all where !symbol.allSatisfy(\.isNumber) {
            XCTAssertNotEqual(SymbolKeyboard.accessibilityLabel(for: symbol), symbol, symbol)
        }
    }

    func testBracketPairsRemainAdjacentOnSamePageAndWideBank() throws {
        let layout = SymbolLayout.make(in: CGRect(x: 0, y: 0, width: 744, height: 280), needsGlobe: true)
        let gap = try XCTUnwrap(layout.centerGap)
        for (open, close) in [("(", ")"), ("[", "]"), ("{", "}"), ("<", ">")] {
            let page = try XCTUnwrap(SymbolKeyboard.pages.first { $0.contains(open) })
            let first = try XCTUnwrap(page.firstIndex(of: open))
            let second = try XCTUnwrap(page.firstIndex(of: close))
            XCTAssertEqual(second, first + 1)
            let a = try XCTUnwrap(layout.frames["symbol-\(first)"])
            let b = try XCTUnwrap(layout.frames["symbol-\(second)"])
            XCTAssertEqual(a.minY, b.minY)
            XCTAssertTrue((a.maxX <= gap.minX && b.maxX <= gap.minX)
                          || (a.minX >= gap.maxX && b.minX >= gap.maxX))
        }
    }

    func testAllKeysFitAcross48ScreenAndGlobeConditions() {
        for width: CGFloat in [320, 390, 599, 600, 744, 900] {
            for height: CGFloat in [180, 239, 240, 300] {
                for globe in [false, true] {
                    let area = CGRect(x: 13, y: 27, width: width, height: height)
                    let layout = SymbolLayout.make(in: area, needsGlobe: globe)
                    let expected = Set(symbolIDs + ["page", "delete", "mode", "space", "return"]
                                       + (globe ? ["globe"] : []) + (width >= 600 ? ["space-right"] : []))
                    XCTAssertEqual(Set(layout.frames.keys), expected)
                    for (key, frame) in layout.frames {
                        XCTAssertGreaterThan(frame.width, 0, key)
                        XCTAssertGreaterThan(frame.height, 0, key)
                        XCTAssertGreaterThanOrEqual(frame.minX, area.minX - 0.0001, key)
                        XCTAssertGreaterThanOrEqual(frame.minY, area.minY - 0.0001, key)
                        XCTAssertLessThanOrEqual(frame.maxX, area.maxX + 0.0001, key)
                        XCTAssertLessThanOrEqual(frame.maxY, area.maxY + 0.0001, key)
                        if let gap = layout.centerGap { XCTAssertFalse(frame.intersects(gap), key) }
                    }
                    let keys = layout.frames.keys.sorted()
                    for (index, key) in keys.enumerated() {
                        for other in keys.dropFirst(index + 1) {
                            XCTAssertFalse(layout.frames[key]!.intersects(layout.frames[other]!), "\(key) / \(other)")
                        }
                    }
                }
            }
        }
    }

    func testRotationKeepsSymbolSlotOrderAndPageDeletePositions() throws {
        let rows = [(0..<10).map { "symbol-\($0)" }, (10..<20).map { "symbol-\($0)" },
                    ["page"] + (20..<28).map { "symbol-\($0)" } + ["delete"]]
        for width: CGFloat in [320, 599, 600, 900] {
            let area = CGRect(x: 7, y: 11, width: width, height: 270)
            let layout = SymbolLayout.make(in: area, needsGlobe: true)
            for (index, row) in rows.enumerated() {
                let first = try XCTUnwrap(layout.frames[row[0]])
                XCTAssertEqual(first.minY, area.minY + CGFloat(index) * (first.height + 6), accuracy: 0.0001)
                for (previous, next) in zip(row, row.dropFirst()) {
                    let a = try XCTUnwrap(layout.frames[previous]), b = try XCTUnwrap(layout.frames[next])
                    XCTAssertEqual(a.minY, b.minY)
                    XCTAssertLessThan(a.maxX, b.minX)
                }
            }
            if width < 600 {
                XCTAssertNil(layout.centerGap)
                XCTAssertNil(layout.frames["space-right"])
            } else {
                let gap = try XCTUnwrap(layout.centerGap)
                XCTAssertEqual(gap.midX, area.midX, accuracy: 0.0001)
                XCTAssertGreaterThanOrEqual(gap.width, 96)
                XCTAssertEqual(gap.minY, area.minY)
                XCTAssertEqual(gap.height, area.height)
            }
        }
    }

    func testBottomSpacesStayInTheirBanksAndControlsKeepFivePointGaps() throws {
        for width: CGFloat in [320, 600, 900] {
            for height: CGFloat in [239, 240] {
                for globe in [false, true] {
                    let area = CGRect(x: 0, y: 20, width: width, height: height)
                    let layout = SymbolLayout.make(in: area, needsGlobe: globe)
                    let rows = width < 600
                        ? [(globe ? ["globe"] : []) + ["mode", "space", "return"]]
                        : [(globe ? ["globe"] : []) + ["mode", "space"], ["space-right", "return"]]
                    for keys in rows {
                        for key in keys {
                            let frame = try XCTUnwrap(layout.frames[key])
                            XCTAssertEqual(frame.height, 44)
                            XCTAssertEqual(frame.maxY, area.maxY, accuracy: 0.0001)
                        }
                        for (previous, next) in zip(keys, keys.dropFirst()) {
                            XCTAssertEqual(try XCTUnwrap(layout.frames[next]).minX - XCTUnwrap(layout.frames[previous]).maxX, 5, accuracy: 0.0001)
                        }
                    }
                    XCTAssertGreaterThanOrEqual(try XCTUnwrap(layout.frames["space"]).width, 64)
                    if let gap = layout.centerGap {
                        XCTAssertLessThanOrEqual(try XCTUnwrap(layout.frames["space"]).maxX, gap.minX)
                        XCTAssertGreaterThanOrEqual(try XCTUnwrap(layout.frames["space-right"]).minX, gap.maxX)
                    }
                }
            }
        }
    }

    func testInvalidAndTooSmallAreasDoNotCreateTouchableFrames() {
        let invalid = [CGRect.zero,
                       CGRect(x: 0, y: 0, width: -320, height: 240),
                       CGRect(x: 0, y: 0, width: 320, height: -240),
                       CGRect(x: 0, y: 0, width: 40, height: 240),
                       CGRect(x: 0, y: 0, width: 320, height: 58),
                       CGRect(x: CGFloat.nan, y: 0, width: 320, height: 240),
                       CGRect(x: 0, y: CGFloat.infinity, width: 320, height: 240),
                       CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 240),
                       CGRect(x: 0, y: 0, width: 320, height: CGFloat.nan)]
        for area in invalid {
            let layout = SymbolLayout.make(in: area, needsGlobe: true)
            XCTAssertTrue(layout.frames.isEmpty, "\(area)")
            XCTAssertNil(layout.centerGap)
        }
    }
}
