import CoreGraphics

/// Heights are in points, not physical pixels. Touch geometry takes priority
/// over the preferred screen fraction on short displays.
public enum KeyboardSizing {
    public static func contentHeight(screenHeight: CGFloat, bottomInset: CGFloat) -> CGFloat {
        guard screenHeight.isFinite, screenHeight > 0, bottomInset.isFinite else { return 286 }
        let bottom = max(0, bottomInset)
        return max(220, min(320 - bottom, screenHeight * 0.33 - bottom))
    }

    public struct Metrics {
        public let header: CGFloat
        public let bottom: CGFloat
        public let barHeight: CGFloat
        public let barY: CGFloat
        public let padY: CGFloat
        public let padHeight: CGFloat
        public let wideSymbols: Bool
        public let showQuickSymbols: Bool
        public let reserved: CGFloat
        public let diameter: CGFloat
    }

    public static func metrics(width: CGFloat, height: CGFloat, bottomInset: CGFloat) -> Metrics {
        let compact = height < 286
        let header: CGFloat = compact ? 0 : 24
        let bottom = max(6, bottomInset)
        let barHeight: CGFloat = 44
        let padY: CGFloat = 4 + (compact ? 0 : header + 6)
        let barY = max(padY + 6, height - bottom - barHeight)
        let padHeight = max(0, barY - 6 - padY)
        let wideSymbols = width >= 2 * min(padHeight, 280) + 3 * 54 + 4 * 6
        let reserved: CGFloat = 0
        let diameter = max(0, min((width - 14) / 2, padHeight - reserved, 280))
        return Metrics(header: header, bottom: bottom, barHeight: barHeight,
                       barY: barY, padY: padY, padHeight: padHeight,
                       wideSymbols: wideSymbols, showQuickSymbols: !compact,
                       reserved: reserved, diameter: diameter)
    }
}
