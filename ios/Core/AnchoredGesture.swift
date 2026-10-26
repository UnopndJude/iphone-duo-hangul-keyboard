import Foundation
import CoreGraphics

/// Circular starting sector selects the key once; cardinal flick selects output.
public struct AnchoredGesture {
    private var gesture = GestureClassifier(cardinalFlicks: true)
    private var key: JoystickMapping.Key?
    public var base: String? { key?.label }
    public var preview: GesturePreview { gesture.preview }
    public var candidate: String? {
        guard let key, preview.kind == .tap || preview.kind == .direction,
              let direction = preview.direction else { return nil }
        return key.outputs[direction]
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
    public mutating func move(to point: CGPoint) { gesture.move(to: point) }
    public mutating func end(at point: CGPoint) -> KeyboardAction? {
        guard gesture.active else { return nil }
        gesture.move(to: point)
        let action = candidate == nil ? nil : preview.direction.flatMap { key?.action($0) }
        _ = gesture.end(at: point)
        key = nil
        return action
    }
    public mutating func cancel() { gesture.cancel(); key = nil }
}
