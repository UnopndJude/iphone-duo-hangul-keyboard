import CoreGraphics

/// Basic English typing state. Capitalization is always an explicit user action.
public struct EnglishKeyboard {
    public enum LetterCase: Equatable { case lower, upper, locked }
    public static let rows: [[String]] = ["qwertyuiop", "asdfghjkl", "zxcvbnm"].map { $0.map(String.init) }
    /// Downward flicks enter symbols and do not consume one-shot Shift.
    public static let flickSymbols: [String: String] = [
        "q":"1", "w":"2", "e":"3", "r":"4", "t":"5",
        "y":"6", "u":"7", "i":"8", "o":"9", "p":"0",
        "a":"@", "s":"#", "d":"$", "f":"%", "g":"&",
        "h":"-", "j":"+", "k":"(", "l":")",
        "z":"!", "x":"?", "c":":", "v":";", "b":"/", "n":",", "m":"~"
    ]
    /// A deliberate vertical movement selects the first detected direction.
    public static func flickDirection(dx: CGFloat, dy: CGFloat) -> Int {
        guard dx.isFinite, dy.isFinite, abs(dy) >= 18, abs(dy) > abs(dx) else { return 0 }
        return dy < 0 ? -1 : 1
    }
    public static func flickAction(for letter: String) -> KeyboardAction? {
        flickSymbols[letter].map { .literal($0) }
    }
    public private(set) var letterCase: LetterCase = .lower

    public init() {}

    /// A tap enables one capital letter, or turns either capital mode off.
    public mutating func toggleShift() {
        letterCase = letterCase == .lower ? .upper : .lower
    }

    /// A long press keeps capitals on until the user turns them off.
    public mutating func toggleCapsLock() {
        letterCase = letterCase == .locked ? .lower : .locked
    }

    /// Only one lowercase ASCII letter is a valid key. Invalid input does not
    /// consume a pending one-letter shift.
    public mutating func input(_ lower: String) -> KeyboardAction? {
        guard lower.utf8.count == 1, let byte = lower.utf8.first, (97...122).contains(byte) else { return nil }
        let output = letterCase == .lower ? lower : lower.uppercased()
        if letterCase == .upper { letterCase = .lower }
        return .literal(output)
    }

    /// An upward flick explicitly enters this letter in uppercase. A pending
    /// one-shot Shift is consumed; Caps Lock stays active.
    public mutating func inputUppercase(_ lower: String) -> KeyboardAction? {
        guard lower.utf8.count == 1, let byte = lower.utf8.first, (97...122).contains(byte) else { return nil }
        if letterCase == .upper { letterCase = .lower }
        return .literal(lower.uppercased())
    }

    public mutating func resetShift() { letterCase = .lower }
}
