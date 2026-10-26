/// Basic English typing state. Capitalization is always an explicit user action.
public struct EnglishKeyboard {
    public enum LetterCase: Equatable { case lower, upper, locked }
    public static let rows: [[String]] = ["qwertyuiop", "asdfghjkl", "zxcvbnm"].map { $0.map(String.init) }
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

    public mutating func resetShift() { letterCase = .lower }
}
