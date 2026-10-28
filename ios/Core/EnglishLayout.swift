import CoreGraphics

/// QWERTY key geometry. The caller supplies the input area below its header.
/// Coordinates remain in the caller's coordinate space; the center gap has no keys.
public enum EnglishLayout {
    public struct Layout {
        public let frames: [String: CGRect]
        public let centerGap: CGRect?
    }

    public static func make(in area: CGRect, needsGlobe: Bool, needsDismiss: Bool = false) -> Layout {
        let empty = Layout(frames: [:], centerGap: nil)
        guard area.origin.x.isFinite, area.origin.y.isFinite,
              area.size.width.isFinite, area.size.height.isFinite,
              area.size.width > 0, area.size.height > 0,
              area.maxX.isFinite, area.maxY.isFinite else { return empty }

        let keyGap: CGFloat = 5
        let rowGap: CGFloat = 6
        let bottomHeight: CGFloat = 44
        let rowHeight = (area.height - bottomHeight - rowGap * 3) / 3
        guard rowHeight > 0 else { return empty }
        let bottomY = area.maxY - bottomHeight
        var frames: [String: CGRect] = [:]

        func row(_ keys: [(String, CGFloat)], bankX: CGFloat, unit: CGFloat, index: Int, offset: CGFloat = 0) {
            var position = offset
            for (key, span) in keys {
                frames[key] = CGRect(x: bankX + position * unit + keyGap / 2,
                                     y: area.minY + CGFloat(index) * (rowHeight + rowGap),
                                     width: span * unit - keyGap, height: rowHeight)
                position += span
            }
        }

        func bottom(_ keys: [String], x: CGFloat, width: CGFloat, fixed: CGFloat, space: String) {
            let spaceWidth = width - CGFloat(keys.count - 1) * (fixed + keyGap)
            var position = x
            for key in keys {
                let keyWidth = key == space ? spaceWidth : fixed
                frames[key] = CGRect(x: position, y: bottomY, width: keyWidth, height: bottomHeight)
                position += keyWidth + keyGap
            }
        }

        if area.width < 600 {
            let unit = area.width / 10
            let keys = (needsGlobe ? ["globe"] : []) + ["mode", "language", "space", "quote", "period", "return"] + (needsDismiss ? ["dismiss"] : [])
            let fixed = min(44, (area.width - CGFloat(keys.count - 1) * keyGap - 64) / CGFloat(keys.count - 1))
            guard unit > keyGap, fixed > 0 else { return empty }
            row("qwertyuiop".map { (String($0), 1) }, bankX: area.minX, unit: unit, index: 0)
            row("asdfghjkl".map { (String($0), 1) }, bankX: area.minX, unit: unit, index: 1, offset: 0.5)
            row([("shift", 1.5)] + "zxcvbnm".map { (String($0), 1) } + [("delete", 1.5)],
                bankX: area.minX, unit: unit, index: 2)
            bottom(keys, x: area.minX, width: area.width, fixed: fixed, space: "space")
            return Layout(frames: frames, centerGap: nil)
        }

        let bankWidth = min(320, (area.width - 96) / 2)
        let unit = bankWidth / 5
        let rightX = area.maxX - bankWidth
        guard unit > keyGap else { return empty }
        row("qwert".map { (String($0), 1) }, bankX: area.minX, unit: unit, index: 0)
        row("yuiop".map { (String($0), 1) }, bankX: rightX, unit: unit, index: 0)
        row("asdfg".map { (String($0), 1) }, bankX: area.minX, unit: unit, index: 1)
        row("hjkl".map { (String($0), 1) }, bankX: rightX, unit: unit, index: 1, offset: 0.5)
        row([("shift", 1)] + "zxcv".map { (String($0), 1) }, bankX: area.minX, unit: unit, index: 2)
        row("bnm".map { (String($0), 1) } + [("delete", 2)], bankX: rightX, unit: unit, index: 2)
        bottom((needsGlobe ? ["globe"] : []) + ["mode", "language", "space"],
               x: area.minX, width: bankWidth, fixed: 44, space: "space")
        bottom(["space-right", "quote", "period", "return"] + (needsDismiss ? ["dismiss"] : []),
               x: rightX, width: bankWidth, fixed: 44, space: "space-right")
        return Layout(frames: frames,
                      centerGap: CGRect(x: area.minX + bankWidth, y: area.minY,
                                        width: area.width - bankWidth * 2, height: area.height))
    }
}
