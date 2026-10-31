import CoreGraphics

/// Space-key drag locks to its first axis and never produces a space,
/// including when the finger returns to the starting point.
public struct SpaceCursorGesture {
    private var origin: CGPoint?
    private var anchorX: CGFloat = 0
    private var anchorY: CGFloat = 0
    private var vertical = false
    private var queuedVerticalSteps = 0
    public private(set) var isDragging = false
    private var cancelled = false
    public init() {}
    public mutating func begin(at point: CGPoint) {
        origin = point; anchorX = point.x; anchorY = point.y; vertical = false; queuedVerticalSteps = 0; isDragging = false; cancelled = false
    }
    public mutating func move(to point: CGPoint) -> Int {
        guard let origin, !cancelled, point.x.isFinite, point.y.isFinite else { return 0 }
        if !isDragging {
            let dx = point.x - origin.x, dy = point.y - origin.y
            guard max(abs(dx), abs(dy)) >= 14 else { return 0 }
            guard abs(dx) != abs(dy) else { return 0 }
            isDragging = true
            vertical = abs(dy) > abs(dx)
            if vertical {
                anchorY = point.y
                queuedVerticalSteps = dy > 0 ? 1 : -1
                return 0
            }
            anchorX = point.x
            return dx > 0 ? 1 : -1
        }
        if vertical {
            let steps = max(-8, min(8, Int((point.y - anchorY) / 30)))
            if steps != 0 { anchorY += CGFloat(steps) * 30; queuedVerticalSteps += steps }
            return 0
        }
        let steps = Int((point.x - anchorX) / 12)
        let bounded = max(-32, min(32, steps))
        if bounded != 0 { anchorX += CGFloat(bounded) * 12 }
        return bounded
    }
    public mutating func takeVerticalSteps() -> Int {
        defer { queuedVerticalSteps = 0 }
        return queuedVerticalSteps
    }
    public var suppressesSpace: Bool { isDragging || cancelled }
    public mutating func cancel() { origin = nil; cancelled = true; isDragging = false }
}

/// UTF-16 offset to a neighbouring newline-delimited line. The proxy cannot
/// expose visual wrapping or prove that its context is complete.
public enum CursorLine {
    public static func offset(before: String?, after: String?, direction: Int) -> Int? {
        guard let before, direction != 0 else { return nil }
        let column = before.split(separator: "\n", omittingEmptySubsequences: false).last.map(String.init) ?? ""
        if direction < 0 {
            guard let end = before.lastIndex(of: "\n") else { return nil }
            let prefix = String(before[..<end])
            let previous = prefix.split(separator: "\n", omittingEmptySubsequences: false).last.map(String.init) ?? ""
            let position = min(column.count, previous.count)
            return -(String(previous.dropFirst(position)) + "\n" + column).utf16.count
        }
        guard let after, let end = after.firstIndex(of: "\n") else { return nil }
        let rest = String(after[after.index(after: end)...])
        let next = rest.split(separator: "\n", omittingEmptySubsequences: false).first.map(String.init) ?? ""
        let suffix = String(after[...end])
        return (suffix + String(next.prefix(column.count))).utf16.count
    }
}
