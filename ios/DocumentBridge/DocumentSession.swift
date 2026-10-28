import Foundation
#if canImport(ThreePadCore)
import ThreePadCore
#endif

/// The small part of UITextDocumentProxy needed by composition. No document
/// contents are persisted or transmitted. Explicit block deletion is bounded.
public protocol KeyboardDocument: AnyObject {
    var identifier: UUID { get }
    var before: String? { get }
    var after: String? { get }
    var selected: String? { get }
    func setMarkedText(_ text: String, selectedRange: NSRange)
    func unmarkText()
    func insertText(_ text: String)
    func adjustTextPosition(byCharacterOffset offset: Int)
    func deleteBackward()
}

public final class DocumentSession {
    private struct Context: Equatable {
        let identifier: UUID
        let before: String?
        let after: String?
        let selected: String?
        init(_ document: KeyboardDocument) {
            identifier = document.identifier
            before = document.before.map { String($0.suffix(256)) }
            after = document.after.map { String($0.prefix(256)) }
            selected = document.selected.flatMap { $0.isEmpty ? nil : String($0.prefix(256)) }
        }
    }

    private var model = ThreePadModel()
    private var expectedContext: Context?
    public private(set) var isUpdating = false
    public var composition: String { model.text }
    public var target: String? { model.target }
    public var canUndoModifier: Bool { model.canUndoModifier }

    public init() {}

    /// Call when the host reports changed text. Matching notifications caused
    /// by our own writes are harmless. Return true only when an external
    /// document/cursor change ended ownership, so the UI can cancel its touches.
    @discardableResult
    public func synchronize(with document: KeyboardDocument) -> Bool {
        guard !isUpdating, let expected = expectedContext else { return false }
        let context = Context(document)
        if context.identifier != expected.identifier {
            // A new field can own its own marked range. Never unmark it using
            // composition state left over from the previous field.
            model.reset()
            expectedContext = context
            return true
        } else if context != expected {
            finish(in: document)
            return true
        }
        return false
    }

    /// Commit on a known boundary or keyboard disappearance. Selection callbacks
    /// must instead synchronize their resulting context: they may be delayed
    /// notifications produced by our own setMarkedText call.
    public func finish(in document: KeyboardDocument) {
        guard !isUpdating else { return }
        isUpdating = true
        if !model.text.isEmpty, expectedContext?.identifier == document.identifier { document.unmarkText() }
        model.reset()
        expectedContext = Context(document)
        isUpdating = false
    }

    /// Commit composition without adding whitespace, then move whole visible
    /// characters. UIKit text offsets use UTF-16 storage positions.
    public func moveCursor(by steps: Int, in document: KeyboardDocument) {
        guard !isUpdating, steps != 0 else { return }
        synchronize(with: document)
        _ = write(to: document) {
            if !self.model.text.isEmpty {
                let composition = self.model.text
                self.model.reset()
                document.insertText(composition)
            }
            let bounded = max(-32, min(32, steps))
            let context = bounded < 0 ? document.before : document.after
            let offset: Int
            if let context {
                let characters = bounded < 0 ? String(context.suffix(-bounded)) : String(context.prefix(bounded))
                offset = characters.utf16.count * (bounded < 0 ? -1 : 1)
            } else {
                offset = bounded < 0 ? -1 : 1
            }
            if offset != 0 { document.adjustTextPosition(byCharacterOffset: offset) }
            return true
        }
    }

    /// Move only through visible newline-delimited context; no guessing when
    /// the host hides text or exposes a selected range.
    public func moveLine(by steps: Int, in document: KeyboardDocument) {
        guard !isUpdating, steps != 0 else { return }
        synchronize(with: document)
        _ = write(to: document) {
            if !self.model.text.isEmpty {
                let composition = self.model.text
                self.model.reset()
                document.insertText(composition)
            }
            guard document.selected?.isEmpty != false else { return false }
            let direction = steps < 0 ? -1 : 1
            for _ in 0..<min(abs(steps), 8) {
                guard let offset = CursorLine.offset(before: document.before, after: document.after, direction: direction), offset != 0 else { break }
                document.adjustTextPosition(byCharacterOffset: offset)
            }
            return true
        }
    }

    @discardableResult
    public func apply(_ action: KeyboardAction, to document: KeyboardDocument) -> Bool {
        guard !isUpdating else { return false }
        synchronize(with: document)

        switch action {
        case .commit:
            finish(in: document)
            return true
        case .literal(let literal):
            guard literal.count == 1 else { return false }
            return write(to: document) {
                // insertText replaces and commits the current marked range.
                // Include its contents in this one write: unmarkText followed
                // by a separate insertion depends on the remote host having
                // already cleared the mark when it receives the insertion.
                let composition = self.model.text
                self.model.reset()
                if literal == "\n", !composition.isEmpty {
                    // Commit the marked range first. A standalone newline must
                    // reach the host as a return, not part of marked replacement.
                    document.insertText(composition)
                    document.insertText("\n")
                } else {
                    document.insertText(composition + literal)
                }
                return true
            }
        case .deleteBlock where model.text.isEmpty:
            return write(to: document) {
                let hasSelection = document.selected.map { !$0.isEmpty } ?? false
                let count = hasSelection ? 1 : DeletionBlock.count(before: document.before)
                for _ in 0..<count { document.deleteBackward() }
                return count > 0
            }
        case .delete where model.text.isEmpty:
            // After a cursor move or a committed boundary this is the host's
            // ordinary delete, including deleting an existing selection.
            return write(to: document) { document.deleteBackward(); return true }
        default:
            break
        }

        return write(to: document) {
            guard self.model.apply(action) else { return false }
            let text = self.model.text
            document.setMarkedText(text, selectedRange: NSRange(location: text.utf16.count, length: 0))
            if text.isEmpty { document.unmarkText() }
            return true
        }
    }

    private func write(to document: KeyboardDocument, _ operation: () -> Bool) -> Bool {
        isUpdating = true
        defer { expectedContext = Context(document); isUpdating = false }
        return operation()
    }
}
