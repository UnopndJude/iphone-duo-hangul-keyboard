import Foundation

public enum Pad: String, CaseIterable { case c, v, m }
public enum Direction: String, CaseIterable { case tap, n, ne, e, se, s, sw, w, nw }

public enum KeyboardAction: Equatable {
    case pad(Pad, Direction)
    case jamo(String)
    case deleteBlock, delete, literal(String), undo, redo, clear, commit
}

/// The accepted V5 mapping. Positions are directions relative to touch-down.
public enum ThreePadMapping {
    public static let c: [Direction: String] = [
        .tap: "ㅇ", .n: "ㄱ", .ne: "ㄴ", .e: "ㄷ", .se: "ㄹ", .s: "ㅁ", .sw: "ㅂ", .w: "ㅅ", .nw: "ㅈ"
    ]
    public static let v: [Direction: String] = [
        .tap: "ㅣ", .n: "ㅗ", .ne: "ㅐ", .e: "ㅏ", .se: "ㅡ", .s: "ㅜ", .sw: "ㅢ", .w: "ㅓ", .nw: "ㅔ"
    ]
    public static let stroke = [
        "ㄱ": "ㅋ", "ㄷ": "ㅌ", "ㅂ": "ㅍ", "ㅈ": "ㅊ", "ㅇ": "ㅎ",
        "ㅏ": "ㅑ", "ㅓ": "ㅕ", "ㅗ": "ㅛ", "ㅜ": "ㅠ", "ㅐ": "ㅒ", "ㅔ": "ㅖ"
    ]
    public static let tense = ["ㄱ": "ㄲ", "ㄷ": "ㄸ", "ㅂ": "ㅃ", "ㅅ": "ㅆ", "ㅈ": "ㅉ"]
    public static let joins = [
        "ㅑㅣ": "ㅒ", "ㅕㅣ": "ㅖ", "ㅗㅏ": "ㅘ", "ㅗㅐ": "ㅙ", "ㅗㅣ": "ㅚ", "ㅜㅓ": "ㅝ", "ㅜㅔ": "ㅞ", "ㅜㅣ": "ㅟ", "ㅡㅣ": "ㅢ"
    ]

    public static func symbol(pad: Pad, direction: Direction) -> String? {
        switch pad {
        case .c: return c[direction]
        case .v: return v[direction]
        case .m: return [.tap: "취소", .n: "덧획", .s: "된소리"][direction]
        }
    }

    /// Canonical actions for tests, examples, and accessibility tutorials.
    /// Unsupported characters return nil rather than silently replacing input.
    public static func encodeJamo(_ jamo: String) -> [KeyboardAction]? {
        for pad in [Pad.c, .v] {
            for direction in Direction.allCases where symbol(pad: pad, direction: direction) == jamo {
                return [.pad(pad, direction)]
            }
        }
        for (direction, mapping) in [(Direction.n, stroke), (.s, tense)] {
            if let entry = mapping.first(where: { $0.value == jamo }), let base = encodeJamo(entry.key) {
                return base + [.pad(.m, direction)]
            }
        }
        if let pair = joins.first(where: { $0.value == jamo })?.key ?? HangulComposer.split[jamo]?.joined() {
            var actions: [KeyboardAction] = []
            for component in pair {
                guard let encoded = encodeJamo(String(component)) else { return nil }
                actions += encoded
            }
            return actions
        }
        return nil
    }

    public static func encodeText(_ text: String) -> [KeyboardAction] {
        text.flatMap { character -> [KeyboardAction] in
            let value = String(character)
            if let jamo = HangulComposer.decompose(value) {
                return jamo.flatMap { encodeJamo($0) ?? [] }
            }
            return encodeJamo(value) ?? [.literal(value)]
        }
    }
}
