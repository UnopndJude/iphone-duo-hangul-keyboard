import XCTest
import CoreGraphics
@testable import ThreePadCore

final class EnglishLayoutTests: XCTestCase {
    private let letters = "abcdefghijklmnopqrstuvwxyz".map(String.init)
    private let controls = ["shift", "delete", "mode", "language", "space", "quote", "period", "return"]

    func testRequiredKeysFitAndNeverOverlapAcrossWidthsHeightsAndGlobeModes() {
        for width: CGFloat in [320, 390, 599, 600, 744, 900] {
            for height: CGFloat in [180, 239, 240, 300] {
                for globe in [false, true] {
                    let area = CGRect(x: 13, y: 27, width: width, height: height)
                    let layout = EnglishLayout.make(in: area, needsGlobe: globe)
                    let expected = Set(letters + controls + (globe ? ["globe"] : []) + (width >= 600 ? ["space-right"] : []))
                    XCTAssertEqual(Set(layout.frames.keys), expected, "\(width) × \(height), globe \(globe)")
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
                            XCTAssertFalse(layout.frames[key]!.intersects(layout.frames[other]!), "\(key) overlaps \(other)")
                        }
                    }
                }
            }
        }
    }

    func testNarrowRowsHaveStandardOrderOffsetsAndControlSpans() throws {
        for width: CGFloat in [320, 390, 599] {
            let area = CGRect(x: 7, y: 11, width: width, height: 270)
            let layout = EnglishLayout.make(in: area, needsGlobe: true)
            let unit = width / 10
            XCTAssertNil(layout.centerGap)
            XCTAssertNil(layout.frames["space-right"])
            for row in EnglishKeyboard.rows {
                for (previous, next) in zip(row, row.dropFirst()) {
                    let a = try XCTUnwrap(layout.frames[previous]), b = try XCTUnwrap(layout.frames[next])
                    XCTAssertEqual(a.minY, b.minY)
                    XCTAssertEqual(b.minX - a.minX, unit, accuracy: 0.0001)
                }
            }
            XCTAssertEqual(try XCTUnwrap(layout.frames["q"]).minX, area.minX + 2.5, accuracy: 0.0001)
            XCTAssertEqual(try XCTUnwrap(layout.frames["a"]).minX, area.minX + 0.5 * unit + 2.5, accuracy: 0.0001)
            XCTAssertEqual(try XCTUnwrap(layout.frames["z"]).minX, area.minX + 1.5 * unit + 2.5, accuracy: 0.0001)
            for key in ["shift", "delete"] {
                XCTAssertEqual(try XCTUnwrap(layout.frames[key]).width, 1.5 * unit - 5, accuracy: 0.0001)
            }
            XCTAssertGreaterThanOrEqual(try XCTUnwrap(layout.frames["space"]).width, 64 - 0.0001)
        }
    }

    func testWideBanksKeepCenterEmptyAndHaveSpacesOnBothSides() throws {
        for width: CGFloat in [600, 744, 900] {
            let area = CGRect(x: 19, y: 23, width: width, height: 280)
            let layout = EnglishLayout.make(in: area, needsGlobe: true)
            let gap = try XCTUnwrap(layout.centerGap)
            let bankWidth = min(320, (width - 96) / 2)
            XCTAssertEqual(gap.midX, area.midX, accuracy: 0.0001)
            XCTAssertEqual(gap.width, width - bankWidth * 2, accuracy: 0.0001)
            XCTAssertGreaterThanOrEqual(gap.width, 96)
            XCTAssertEqual(gap.minY, area.minY); XCTAssertEqual(gap.height, area.height)
            for key in "qwertasdfgzxcv".map(String.init) + ["shift", "globe", "mode", "language", "space"] {
                XCTAssertLessThanOrEqual(try XCTUnwrap(layout.frames[key]).maxX, gap.minX + 0.0001, key)
            }
            for key in "yuiophjklbnm".map(String.init) + ["delete", "space-right", "quote", "period", "return"] {
                XCTAssertGreaterThanOrEqual(try XCTUnwrap(layout.frames[key]).minX, gap.maxX - 0.0001, key)
            }
            XCTAssertEqual(try XCTUnwrap(layout.frames["h"]).minX,
                           area.maxX - bankWidth + bankWidth / 10 + 2.5, accuracy: 0.0001)
            XCTAssertEqual(try XCTUnwrap(layout.frames["delete"]).width, bankWidth * 2 / 5 - 5, accuracy: 0.0001)
        }
    }

    func testBottomRowsHaveFivePointGapsAndExpectedHeight() throws {
        for width: CGFloat in [320, 600, 900] {
            for height: CGFloat in [239, 240] {
                for globe in [false, true] {
                    let area = CGRect(x: 0, y: 20, width: width, height: height)
                    let layout = EnglishLayout.make(in: area, needsGlobe: globe)
                    let rows = width < 600
                        ? [(globe ? ["globe"] : []) + ["mode", "language", "space", "quote", "period", "return"]]
                        : [(globe ? ["globe"] : []) + ["mode", "language", "space"], ["space-right", "quote", "period", "return"]]
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
                    let first = try XCTUnwrap(layout.frames["q"])
                    let second = try XCTUnwrap(layout.frames["a"])
                    let third = try XCTUnwrap(layout.frames["z"])
                    let bottom = try XCTUnwrap(layout.frames["space"])
                    XCTAssertEqual(second.minY - first.maxY, 6, accuracy: 0.0001)
                    XCTAssertEqual(third.minY - second.maxY, 6, accuracy: 0.0001)
                    XCTAssertEqual(bottom.minY - third.maxY, 6, accuracy: 0.0001)
                }
            }
        }
    }

    func testInvalidAndTooSmallAreasDoNotProduceTouchableFrames() {
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
            let layout = EnglishLayout.make(in: area, needsGlobe: true)
            XCTAssertTrue(layout.frames.isEmpty, "\(area)")
            XCTAssertNil(layout.centerGap)
        }
    }
}
