import Foundation
import CoreGraphics

public struct GesturePreview: Equatable {
    public enum Kind { case tap, direction, uncertain, cancel }
    public var kind: Kind
    public var direction: Direction?
    public var reason: String
    public var origin: CGPoint
    public var delta: CGPoint
}

/// Relative flick classifier in UIKit points. Thresholds are design choices,
/// not estimates of human accuracy. The UI owns and filters the active UITouch.
public struct GestureClassifier {
    public static let tapRadius: CGFloat = 9
    public static let flickRadius: CGFloat = 24
    public static let outsideMargin: CGFloat = 48
    public static let directionHalfAngle: CGFloat = 17.5
    public static let modifierHalfAngle: CGFloat = 30
    private static let epsilon: CGFloat = 1e-9
    private static let sectors: [Direction] = [.e, .se, .s, .sw, .w, .nw, .n, .ne]
    private let cardinalFlicks: Bool
    private struct State {
        var pad: Pad
        var origin: CGPoint
        var location: CGPoint
        var bounds: CGRect
        var maxDistance: CGFloat = 0
        var cancelReason: String?
        var lastDirection: Direction?
    }
    private var state: State?
    private var last = GesturePreview(kind: .cancel, direction: nil, reason: "idle", origin: .zero, delta: .zero)

    public init(cardinalFlicks: Bool = false) { self.cardinalFlicks = cardinalFlicks }
    public var active: Bool { state != nil }
    public var preview: GesturePreview { state.map(classify) ?? last }

    public mutating func begin(pad: Pad, at point: CGPoint, bounds: CGRect) {
        guard state == nil else { return }
        guard Self.finite(point), Self.finite(bounds.origin), bounds.width.isFinite, bounds.height.isFinite,
              bounds.width > 0, bounds.height > 0 else {
            last = GesturePreview(kind: .cancel, direction: nil, reason: "invalid-begin", origin: .zero, delta: .zero)
            return
        }
        guard point.x >= bounds.minX && point.x <= bounds.maxX && point.y >= bounds.minY && point.y <= bounds.maxY else {
            last = GesturePreview(kind: .cancel, direction: nil, reason: "outside-start-pad", origin: point, delta: .zero)
            return
        }
        state = State(pad: pad, origin: point, location: point, bounds: bounds)
    }

    public mutating func move(to point: CGPoint) {
        guard var current = state else { return }
        guard Self.finite(point) else {
            current.cancelReason = current.cancelReason ?? "invalid-coordinate"
            state = current
            return
        }
        current.location = point
        current.maxDistance = max(current.maxDistance, hypot(point.x - current.origin.x, point.y - current.origin.y))
        let dx = max(current.bounds.minX - point.x, 0, point.x - current.bounds.maxX)
        let dy = max(current.bounds.minY - point.y, 0, point.y - current.bounds.maxY)
        if !cardinalFlicks, hypot(dx, dy) > Self.outsideMargin + Self.epsilon {
            current.cancelReason = current.cancelReason ?? "outside-pad-limit"
        }
        let candidate = classify(current)
        if candidate.kind == .direction { current.lastDirection = candidate.direction }
        state = current
    }

    @discardableResult
    public mutating func end(at point: CGPoint) -> KeyboardAction? {
        guard let pad = state?.pad else { return nil }
        move(to: point)
        var result = preview
        state = nil
        if (result.kind == .tap || result.kind == .direction), let direction = result.direction {
            last = result
            return .pad(pad, direction)
        }
        result.kind = .cancel
        last = result
        return nil
    }

    public mutating func cancel(reason: String = "cancelled") {
        var result = preview
        result.kind = .cancel; result.direction = nil; result.reason = reason
        state = nil; last = result
    }

    private static func finite(_ point: CGPoint) -> Bool { point.x.isFinite && point.y.isFinite }
    private static func angleDistance(_ a: CGFloat, _ b: CGFloat) -> CGFloat {
        abs((a - b + 540).truncatingRemainder(dividingBy: 360) - 180)
    }
    private func classify(_ current: State) -> GesturePreview {
        let delta = CGPoint(x: current.location.x - current.origin.x, y: current.location.y - current.origin.y)
        func result(_ kind: GesturePreview.Kind, _ direction: Direction? = nil, _ reason: String) -> GesturePreview {
            GesturePreview(kind: kind, direction: direction, reason: reason, origin: current.origin, delta: delta)
        }
        if let reason = current.cancelReason { return result(.cancel, nil, reason) }
        if current.maxDistance <= Self.tapRadius + Self.epsilon { return result(.tap, .tap, "tap") }
        let distance = hypot(delta.x, delta.y)
        if distance <= Self.tapRadius + Self.epsilon { return result(.cancel, nil, "returned-to-origin") }
        let threshold: CGFloat = cardinalFlicks ? 18 : Self.flickRadius
        if distance < threshold - Self.epsilon { return result(.uncertain, nil, "distance-dead-zone") }
        let angle = (atan2(delta.y, delta.x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
        if cardinalFlicks {
            let sector = Int((angle / 90).rounded()) % 4
            if Self.angleDistance(angle, CGFloat(sector) * 90) <= 40 + Self.epsilon {
                return result(.direction, Self.sectors[sector * 2], "direction")
            }
            // Small diagonal drift keeps the previous direction; a deliberate
            // turn into another cardinal sector updates it. No distance cap.
            if let direction = current.lastDirection { return result(.direction, direction, "held-direction") }
            return result(.uncertain, nil, "angle-gap")
        }
        if current.pad == .m {
            if Self.angleDistance(angle, 270) <= Self.modifierHalfAngle + Self.epsilon { return result(.direction, .n, "direction") }
            if Self.angleDistance(angle, 90) <= Self.modifierHalfAngle + Self.epsilon { return result(.direction, .s, "direction") }
            return result(.uncertain, nil, "modifier-angle-gap")
        }
        let sector = Int((angle / 45).rounded()) % 8
        if Self.angleDistance(angle, CGFloat(sector) * 45) <= Self.directionHalfAngle + Self.epsilon {
            return result(.direction, Self.sectors[sector], "direction")
        }
        return result(.uncertain, nil, "angle-gap")
    }
}
