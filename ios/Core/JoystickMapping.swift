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
        Key(label: "ㄱ", outputs: [.tap:"ㄱ", .n:"ㄲ", .w:"ㅋ", .e:"ㅋ", .s:"5"]),
        Key(label: "ㄴ", outputs: [.tap:"ㄴ", .n:"ㄸ", .s:"ㄷ", .w:"ㅌ", .e:"ㅌ"]),
        Key(label: "ㅁ", outputs: [.tap:"ㅁ", .n:"ㅃ", .s:"ㅂ", .w:"ㅍ", .e:"ㅍ"]),
        Key(label: "ㅇ", outputs: [.tap:"ㅇ", .w:"ㅎ", .e:"ㅎ", .n:"6", .s:"7"]),
        Key(label: "ㅈ", outputs: [.tap:"ㅈ", .n:"ㅉ", .w:"ㅊ", .e:"ㅊ", .s:"~"]),
        Key(label: "ㅅ", outputs: [.tap:"ㅅ", .n:"ㅆ", .w:"8", .e:"9", .s:"0"]),
        Key(label: "ㄹ", outputs: [.tap:"ㄹ", .n:"1", .w:"2", .e:"3", .s:"4"])
    ]
    /// Screenshot-compatible mappings for the narrow Dingul-style grid.
    public static let gridConsonants: [Key] = [
        Key(label: "ㄱ", outputs: [.tap:"ㄱ", .n:"ㄲ", .w:"ㅋ", .e:"ㅋ", .s:"#"]),
        Key(label: "ㄴ", outputs: [.tap:"ㄴ", .n:"ㄸ", .s:"ㄷ", .w:"ㅌ", .e:"ㅌ"]),
        Key(label: "ㄹ", outputs: [.tap:"ㄹ", .n:"^", .w:"=", .e:"-", .s:"_"]),
        Key(label: "ㅁ", outputs: [.tap:"ㅁ", .n:"ㅃ", .s:"ㅂ", .w:"ㅍ", .e:"ㅍ"]),
        Key(label: "ㅅ", outputs: [.tap:"ㅅ", .n:"ㅆ", .w:"1", .s:"2", .e:"3"]),
        Key(label: "ㅇ", outputs: [.tap:"ㅇ", .n:"❤️", .w:"4", .s:"5", .e:"6"]),
        Key(label: "ㅈ", outputs: [.tap:"ㅈ", .n:"ㅉ", .w:"ㅊ", .e:"ㅊ", .s:"~"]),
        Key(label: "ㅎ", outputs: [.tap:"ㅎ", .n:"0", .w:"7", .s:"8", .e:"9"])
    ]
    public static func gridKeys(_ pad: Pad) -> [Key] { pad == .c ? gridConsonants : keys(pad) }

    public static let vowels: [Key] = [
        Key(label: "ㅢ", outputs: [.tap:"ㅢ", .n:"ㅚ", .s:"ㅟ", .w:"ㅝ", .e:"ㅘ"]),
        Key(label: "ㅣ", outputs: [.tap:"ㅣ", .n:"ㅗ", .s:"ㅜ", .w:"ㅓ", .e:"ㅏ"]),
        Key(label: "ㅡ", outputs: [.tap:"ㅡ", .n:"ㅙ", .s:"ㅞ", .w:"ㅔ", .e:"ㅐ"]),
        Key(label: "··", outputs: [.n:"ㅛ", .s:"ㅠ", .w:"ㅕ", .e:"ㅑ"])
    ]
    public static let punctuation: [Key] = [
        Key(label: ".", outputs: [.tap:".", .n:"\"", .w:",", .s:"'", .e:"_"]),
        Key(label: "?", outputs: [.tap:"?", .n:"!", .w:"+", .s:"*", .e:"-"]),
        Key(label: "/", outputs: [.tap:"/", .n:":", .w:"@", .s:";", .e:"="])
    ]
    public static func keys(_ pad: Pad) -> [Key] {
        if pad == .c { return consonants }
        // Interleave punctuation with the three outer vowels. Their angles
        // stay at 0°, 120°, and 240°; ㅣ remains at the centre.
        if pad == .v { return [vowels[0], punctuation[0], vowels[2], punctuation[1], vowels[3], punctuation[2], vowels[1]] }
        return []
    }
    public static func centralKey(_ pad: Pad) -> Key? { keys(pad).first { $0.label == (pad == .c ? "ㅇ" : "ㅣ") } }
    public static func ringKeys(_ pad: Pad) -> [Key] { keys(pad).filter { $0.label != centralKey(pad)?.label } }
    public static func usesGrid(keyboardWidth: CGFloat) -> Bool { keyboardWidth < 600 }

    /// Rows use their complete rectangular cells for hit testing. Only the
    /// drawn key has a gutter, so gaps never discard a valid starting touch.
    public static func gridFrames(pad: Pad, bounds: CGRect) -> [(key: Key, frame: CGRect)] {
        guard bounds.width.isFinite, bounds.height.isFinite, bounds.width > 0, bounds.height > 0 else { return [] }
        let rows: [[String]] = pad == .c
            ? [["ㄱ", "ㄴ"], ["ㄹ", "ㅁ"], ["ㅅ", "ㅇ"], ["ㅈ", "ㅎ"]]
            : pad == .v ? [["ㅢ", "delete"], ["ㅣ", "?"], ["ㅡ", "."], ["··", "/"]] : []
        return rows.enumerated().flatMap { row, labels in
            labels.enumerated().compactMap { column, label in
                guard let key = gridKeys(pad).first(where: { $0.label == label }) else { return nil }
                // The vowel bank contains one full-width vowel column and
                // a narrower symbol column (60% of a letter key).
                let fraction: CGFloat = pad == .v ? 0.625 : 0.5
                let x = column == 0 ? bounds.minX : bounds.minX + bounds.width * fraction
                let width = bounds.width * (column == 0 ? fraction : 1 - fraction)
                return (key, CGRect(x: x, y: bounds.minY + CGFloat(row) * bounds.height / 4,
                                    width: width, height: bounds.height / 4))
            }
        }
    }

    public static func gridControlFrame(in bounds: CGRect) -> CGRect {
        CGRect(x: bounds.minX + bounds.width * 0.625, y: bounds.minY,
               width: bounds.width * 0.375, height: bounds.height / 4)
    }

    public static func gridKey(pad: Pad, at point: CGPoint, bounds: CGRect) -> Key? {
        guard point.x.isFinite, point.y.isFinite, bounds.contains(point) else { return nil }
        return gridFrames(pad: pad, bounds: bounds).first { $0.frame.contains(point) }?.key
    }

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
