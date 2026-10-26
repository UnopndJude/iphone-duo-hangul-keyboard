import Foundation

/// End-of-composition editing. The host must reset when the text cursor changes.
/// Units retain entered vowel components so deleting 괘 produces 고, then ㄱ.
public struct ThreePadModel {
    public static let historyLimit = 180
    private struct Unit { var value: String; var isJamo: Bool }
    private struct ModifierUndo { var index: Int; var before: String }
    private struct Snapshot { var units: [Unit]; var modifierUndo: ModifierUndo? }
    private var units: [Unit] = []
    private var modifierUndo: ModifierUndo?
    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []

    public init() {}
    public var canUndoModifier: Bool { modifierUndo != nil }
    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    public var text: String {
        var output = "", jamo: [String] = []
        for unit in units {
            if unit.isJamo { jamo.append(unit.value) }
            else {
                output += HangulComposer.compose(jamo) + unit.value
                jamo.removeAll(keepingCapacity: true)
            }
        }
        return output + HangulComposer.compose(jamo)
    }

    public var target: String? {
        guard let last = units.last, last.isJamo else { return nil }
        if HangulComposer.initials.contains(last.value) { return last.value }
        guard HangulComposer.vowels.contains(last.value) else { return nil }
        var start = units.count - 1
        while start > 0 && units[start - 1].isJamo && HangulComposer.vowels.contains(units[start - 1].value) {
            start -= 1
        }
        var vowel = ""
        for unit in units[start...] { vowel = ThreePadMapping.joins[vowel + unit.value] ?? unit.value }
        return vowel
    }

    /// Drops the local composition and its undo history without changing host text.
    public mutating func reset() {
        units.removeAll(); modifierUndo = nil; undoStack.removeAll(); redoStack.removeAll()
    }

    @discardableResult
    public mutating func apply(_ action: KeyboardAction) -> Bool {
        switch action {
        case let .jamo(value):
            guard HangulComposer.initials.contains(value) || HangulComposer.vowels.contains(value) else { return false }
            rememberEdit()
            units.append(Unit(value: value, isJamo: true)); modifierUndo = nil
        case let .pad(pad, direction) where pad == .c || pad == .v:
            guard let value = ThreePadMapping.symbol(pad: pad, direction: direction) else { return false }
            rememberEdit()
            units.append(Unit(value: value, isJamo: true)); modifierUndo = nil
        case let .pad(.m, direction):
            if direction == .tap {
                guard let previous = modifierUndo, units.indices.contains(previous.index) else { return false }
                rememberEdit()
                units[previous.index].value = previous.before; modifierUndo = nil
            } else {
                guard let current = target,
                      let next = (direction == .n ? ThreePadMapping.stroke : direction == .s ? ThreePadMapping.tense : [:])[current] else { return false }
                rememberEdit()
                modifierUndo = ModifierUndo(index: units.count - 1, before: units[units.count - 1].value)
                units[units.count - 1].value = next
            }
        case .pad: return false
        case .deleteBlock:
            guard !units.isEmpty else { return false }
            let remaining = text.dropLast(DeletionBlock.count(before: text))
            rememberEdit()
            units = remaining.map { Unit(value: String($0), isJamo: false) }
            modifierUndo = nil
        case .delete:
            guard !units.isEmpty else { return false }
            rememberEdit(); units.removeLast(); modifierUndo = nil
        case let .literal(value):
            guard value.count == 1 else { return false }
            rememberEdit(); units.append(Unit(value: value, isJamo: false)); modifierUndo = nil
        case .commit:
            // A language switch is an undo boundary. Preserve each displayed
            // character as a literal; new jamo cannot recompose it. Clearing
            // both stacks prevents undo from restoring pre-commit jamo state.
            units = text.map { Unit(value: String($0), isJamo: false) }
            modifierUndo = nil; undoStack.removeAll(); redoStack.removeAll()
        case .clear:
            guard !units.isEmpty else { return false }
            rememberEdit(); units.removeAll(); modifierUndo = nil
        case .undo:
            guard let previous = undoStack.popLast() else { return false }
            Self.append(snapshot, to: &redoStack); restore(previous)
        case .redo:
            guard let next = redoStack.popLast() else { return false }
            Self.append(snapshot, to: &undoStack); restore(next)
        }
        return true
    }

    private var snapshot: Snapshot { Snapshot(units: units, modifierUndo: modifierUndo) }
    private mutating func restore(_ state: Snapshot) { units = state.units; modifierUndo = state.modifierUndo }
    private static func append(_ state: Snapshot, to stack: inout [Snapshot]) {
        stack.append(state)
        if stack.count > historyLimit { stack.removeFirst(stack.count - historyLimit) }
    }
    private mutating func rememberEdit() {
        Self.append(snapshot, to: &undoStack); redoStack.removeAll()
    }
}

/// One whitespace-delimited word and trailing spaces, at most 32 graphemes.
/// A newline is its own block; unknown document context falls back to one delete.
public enum DeletionBlock {
    public static func count(before text: String?) -> Int {
        guard let text else { return 1 }
        let tail = Array(text.suffix(32).reversed())
        guard let last = tail.first else { return 0 }
        if last.isNewline { return 1 }
        var count = 0
        while count < tail.count && tail[count].isWhitespace && !tail[count].isNewline { count += 1 }
        while count < tail.count && !tail[count].isWhitespace { count += 1 }
        return count
    }
}
