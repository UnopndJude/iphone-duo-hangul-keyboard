import Foundation
import CoreGraphics

/// Cardinal jamo, ㅈ-down tilde and three punctuation clusters from the official iOS screenshot.
/// Local variation: merged ㅇ/ㅎ and active ㅇ/ㅣ centres. Unverified rightward
/// punctuation gestures and legacy return strokes are deliberately unmapped.
public enum JoystickMapping {
    public struct Key {
        public let label: String
        public let outputs: [Direction: String]
        public func action(_ direction: Direction) -> KeyboardAction? {
            guard let value = outputs[direction] else { return nil }
            return HangulComposer.initials.contains(value) || HangulComposer.vowels.contains(value)
                ? .jamo(value) : .literal(value)
        }
    }
    public static let consonants: [Key] = [
        Key(label: "ㄱ", outputs: [.tap:"ㄱ", .n:"ㄲ", .w:"ㅋ", .e:"ㅋ"]),
        Key(label: "ㄴ", outputs: [.tap:"ㄴ", .n:"ㄸ", .s:"ㄷ", .w:"ㅌ", .e:"ㅌ"]),
        Key(label: "ㅁ", outputs: [.tap:"ㅁ", .n:"ㅃ", .s:"ㅂ", .w:"ㅍ", .e:"ㅍ"]),
        Key(label: "ㅇ", outputs: [.tap:"ㅇ", .w:"ㅎ", .e:"ㅎ"]),
        Key(label: "ㅈ", outputs: [.tap:"ㅈ", .n:"ㅉ", .w:"ㅊ", .e:"ㅊ", .s:"~"]),
        Key(label: "ㅅ", outputs: [.tap:"ㅅ", .n:"ㅆ"]),
        Key(label: "ㄹ", outputs: [.tap:"ㄹ"])
    ]
    public static let vowels: [Key] = [
        Key(label: "ㅢ", outputs: [.tap:"ㅢ", .n:"ㅚ", .s:"ㅟ", .w:"ㅝ", .e:"ㅘ"]),
        Key(label: "ㅣ", outputs: [.tap:"ㅣ", .n:"ㅗ", .s:"ㅜ", .w:"ㅓ", .e:"ㅏ"]),
        Key(label: "ㅡ", outputs: [.tap:"ㅡ", .n:"ㅙ", .s:"ㅞ", .w:"ㅔ", .e:"ㅐ"]),
        Key(label: "··", outputs: [.n:"ㅛ", .s:"ㅠ", .w:"ㅕ", .e:"ㅑ"])
    ]
    public static let punctuation: [Key] = [
        Key(label: ".", outputs: [.tap:".", .n:"\"", .w:",", .s:"'"]),
        Key(label: "?", outputs: [.tap:"?", .n:"!", .w:"+", .s:"*"]),
        Key(label: "/", outputs: [.tap:"/", .n:":", .w:"@", .s:";"])
    ]
    public static func keys(_ pad: Pad) -> [Key] { pad == .c ? consonants : pad == .v ? vowels : [] }
    public static func centralKey(_ pad: Pad) -> Key? { keys(pad).first { $0.label == (pad == .c ? "ㅇ" : "ㅣ") } }
    public static func ringKeys(_ pad: Pad) -> [Key] { keys(pad).filter { $0.label != centralKey(pad)?.label } }
    public static let directions: [(Direction, String)] = [(.n,"↑"), (.e,"→"), (.s,"↓"), (.w,"←")]
    public static let hubRatio: CGFloat = 0.19
    public static let hubGap: CGFloat = 4
    public static func circle(in bounds: CGRect) -> CGRect {
        let diameter = min(bounds.width, bounds.height)
        return CGRect(x: bounds.midX - diameter / 2, y: bounds.midY - diameter / 2, width: diameter, height: diameter)
    }
    public static func center(pad: Pad, index: Int, bounds: CGRect) -> CGPoint {
        let circle = circle(in: bounds)
        let keys = keys(pad)
        guard keys.indices.contains(index) else { return CGPoint(x: circle.midX, y: circle.midY) }
        let ring = ringKeys(pad)
        guard let ringIndex = ring.firstIndex(where: { $0.label == keys[index].label }) else {
            return CGPoint(x: circle.midX, y: circle.midY)
        }
        let angle = -CGFloat.pi / 2 + CGFloat(ringIndex) * 2 * .pi / CGFloat(ring.count)
        let radius = circle.width * 0.35
        return CGPoint(x: circle.midX + cos(angle) * radius, y: circle.midY + sin(angle) * radius)
    }
    /// Active central key; 4pt radial gap and 3-degree sector gaps cancel ambiguous starts.
    public static func key(pad: Pad, at point: CGPoint, bounds: CGRect) -> Key? {
        let entries = ringKeys(pad)
        guard !entries.isEmpty, bounds.origin.x.isFinite, bounds.origin.y.isFinite,
              bounds.width.isFinite, bounds.height.isFinite, bounds.width > 0, bounds.height > 0,
              point.x.isFinite, point.y.isFinite else { return nil }
        let circle = circle(in: bounds)
        let dx = point.x - circle.midX, dy = point.y - circle.midY
        let radius = hypot(dx, dy)
        guard radius <= circle.width / 2 else { return nil }
        if radius <= circle.width * hubRatio { return centralKey(pad) }
        guard radius >= circle.width * hubRatio + hubGap else { return nil }
        let angle = (atan2(dy, dx) * 180 / .pi + 450).truncatingRemainder(dividingBy: 360)
        let step = CGFloat(360) / CGFloat(entries.count)
        let sector = Int((angle / step).rounded()) % entries.count
        let distance = abs((angle - CGFloat(sector) * step + 540).truncatingRemainder(dividingBy: 360) - 180)
        guard distance <= step / 2 - 1.5 else { return nil }
        return entries[sector]
    }
}
