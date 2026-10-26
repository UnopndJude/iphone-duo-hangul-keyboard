import CoreGraphics

/// Geometry for both fixed 28-symbol pages, below the keyboard header.
public enum SymbolLayout {
    public struct Layout {
        public let frames: [String: CGRect]
        public let centerGap: CGRect?
    }

    public static func make(in area: CGRect, needsGlobe: Bool) -> Layout {
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

        func row(_ keys: [String], x: CGFloat, unit: CGFloat, index: Int) {
            for (column, key) in keys.enumerated() {
                frames[key] = CGRect(x: x + CGFloat(column) * unit + keyGap / 2,
                                     y: area.minY + CGFloat(index) * (rowHeight + rowGap),
                                     width: unit - keyGap, height: rowHeight)
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

        let first = (0..<10).map { "symbol-\($0)" }
        let second = (10..<20).map { "symbol-\($0)" }
        let third = ["page"] + (20..<28).map { "symbol-\($0)" } + ["delete"]
        if area.width < 600 {
            let unit = area.width / 10
            let controls = (needsGlobe ? ["globe"] : []) + ["mode", "space", "return"]
            let fixed = min(44, (area.width - CGFloat(controls.count - 1) * keyGap - 64) / CGFloat(controls.count - 1))
            guard unit > keyGap, fixed > 0 else { return empty }
            for (index, keys) in [first, second, third].enumerated() {
                row(keys, x: area.minX, unit: unit, index: index)
            }
            bottom(controls, x: area.minX, width: area.width, fixed: fixed, space: "space")
            return Layout(frames: frames, centerGap: nil)
        }

        let bankWidth = min(320, (area.width - 96) / 2)
        let unit = bankWidth / 5
        let rightX = area.maxX - bankWidth
        guard unit > keyGap else { return empty }
        for (index, keys) in [first, second, third].enumerated() {
            row(Array(keys.prefix(5)), x: area.minX, unit: unit, index: index)
            row(Array(keys.suffix(5)), x: rightX, unit: unit, index: index)
        }
        bottom((needsGlobe ? ["globe"] : []) + ["mode", "space"],
               x: area.minX, width: bankWidth, fixed: 44, space: "space")
        bottom(["space-right", "return"], x: rightX, width: bankWidth, fixed: 44, space: "space-right")
        return Layout(frames: frames,
                      centerGap: CGRect(x: area.minX + bankWidth, y: area.minY,
                                        width: area.width - bankWidth * 2, height: area.height))
    }
}
