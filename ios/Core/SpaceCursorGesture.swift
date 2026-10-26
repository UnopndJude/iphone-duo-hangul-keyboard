import CoreGraphics

/// Horizontal space-key drag. Once activated it never produces a space,
/// including when the finger returns to the starting point.
public struct SpaceCursorGesture {
    private var origin: CGPoint?
    private var anchorX: CGFloat = 0
    public private(set) var isDragging = false
    private var cancelled = false
    public init() {}
    public mutating func begin(at point: CGPoint) {
        origin = point; anchorX = point.x; isDragging = false; cancelled = false
    }
    public mutating func move(to point: CGPoint) -> Int {
        guard let origin, !cancelled, point.x.isFinite, point.y.isFinite else { return 0 }
        if !isDragging {
            let dx = point.x - origin.x, dy = point.y - origin.y
            if abs(dy) >= 24 && abs(dy) > abs(dx) { cancelled = true; return 0 }
            guard abs(dx) >= 14, abs(dx) > abs(dy) else { return 0 }
            isDragging = true
            anchorX = point.x
            return dx > 0 ? 1 : -1
        }
        let steps = Int((point.x - anchorX) / 12)
        let bounded = max(-32, min(32, steps))
        if bounded != 0 { anchorX += CGFloat(bounded) * 12 }
        return bounded
    }
    public var suppressesSpace: Bool { isDragging || cancelled }
    public mutating func cancel() { origin = nil; cancelled = true; isDragging = false }
}
