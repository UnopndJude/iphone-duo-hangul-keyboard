import Foundation
import CoreGraphics

/// Circular starting sector selects the key once; cardinal flick selects output.
public struct AnchoredGesture {
    private var gesture = GestureClassifier(cardinalFlicks: true)
    private var key: JoystickMapping.Key?
    private var horizontalDirection: Direction?
    private var corner: CGPoint?
    private var compoundVowel: String?
    public var base: String? { key?.label }
    public var preview: GesturePreview {
        var state = gesture.preview
        if compoundVowel != nil, state.reason != "invalid-coordinate" {
            state.kind = .direction
            state.direction = horizontalDirection
            state.reason = "compound-reversal"
        }
        return state
    }
    public var candidate: String? {
        guard let key, preview.kind == .tap || preview.kind == .direction,
              let direction = preview.direction else { return nil }
        return compoundVowel ?? key.outputs[direction]
    }
    public init() {}
    public static func symbol(pad: Pad, at point: CGPoint, bounds: CGRect) -> String? {
        JoystickMapping.key(pad: pad, at: point, bounds: bounds)?.label
    }
    public mutating func begin(pad: Pad, at point: CGPoint, bounds: CGRect) {
        guard !gesture.active else { return }
        key = JoystickMapping.key(pad: pad, at: point, bounds: bounds)
        guard key != nil else { return }
        // Starting key stays fixed. Cardinal flicks have no travel limit;
        // returning to the origin remains an explicit way to cancel.
        gesture.begin(pad: .c, at: point, bounds: JoystickMapping.circle(in: bounds))
    }
    public mutating func begin(key: JoystickMapping.Key, at point: CGPoint, bounds: CGRect) {
        guard !gesture.active else { return }
        self.key = key
        gesture.begin(pad: .c, at: point, bounds: bounds)
    }
    public mutating func move(to point: CGPoint) {
        gesture.move(to: point)
        guard gesture.active, (key?.label == "··" || key?.label == "ㅡ"), point.x.isFinite, point.y.isFinite else { return }
        let state = gesture.preview
        if state.reason == "invalid-coordinate" { compoundVowel = nil; return }
        if horizontalDirection == nil, state.kind == .direction,
           state.direction == .e || state.direction == .w {
            horizontalDirection = state.direction
            corner = point
        }
        guard let direction = horizontalDirection, let previous = corner, compoundVowel == nil else { return }
        let forward = direction == .e ? point.x - previous.x : previous.x - point.x
        if forward > 0 {
            corner = point
        } else if forward <= -18 && abs(point.y - previous.y) <= 20 {
            // A deliberate horizontal reversal selects the double vowel.
            // It remains selected even if the finger crosses the origin.
            compoundVowel = direction == .e ? "ㅒ" : "ㅖ"
        }
    }
    public mutating func end(at point: CGPoint) -> KeyboardAction? {
        guard gesture.active else { return nil }
        move(to: point)
        let action: KeyboardAction?
        if let vowel = compoundVowel, candidate == vowel { action = .jamo(vowel) }
        else { action = candidate == nil ? nil : preview.direction.flatMap { key?.action($0) } }
        _ = gesture.end(at: point)
        key = nil
        horizontalDirection = nil; corner = nil; compoundVowel = nil
        return action
    }
    public mutating func cancel() { gesture.cancel(); key = nil; horizontalDirection = nil; corner = nil; compoundVowel = nil }
}
