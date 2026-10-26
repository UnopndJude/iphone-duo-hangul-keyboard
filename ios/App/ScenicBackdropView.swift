import UIKit

/// Local vector illustration shared visually by the input area and glass preview.
/// No network, photo-library permission, or image asset is required.
final class ScenicBackdropView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        contentMode = .redraw
    }
    required init?(coder: NSCoder) { super.init(coder: coder) }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle { setNeedsDisplay() }
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext(), bounds.width > 0, bounds.height > 0 else { return }
        let dark = traitCollection.userInterfaceStyle == .dark
        let sky = dark
            ? [UIColor(red: 0.08, green: 0.17, blue: 0.29, alpha: 1), UIColor(red: 0.21, green: 0.34, blue: 0.40, alpha: 1)]
            : [UIColor(red: 0.63, green: 0.83, blue: 0.91, alpha: 1), UIColor(red: 0.98, green: 0.88, blue: 0.72, alpha: 1)]
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: sky.map(\.cgColor) as CFArray, locations: [0, 1])!
        context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: bounds.height), options: [])
        let w = bounds.width, h = bounds.height
        (dark ? UIColor(white: 0.9, alpha: 0.85) : UIColor(red: 1, green: 0.95, blue: 0.76, alpha: 1)).setFill()
        let sun = min(w, h) * 0.20
        UIBezierPath(ovalIn: CGRect(x: w * 0.70, y: h * 0.22, width: sun, height: sun)).fill()
        func ridge(_ points: [(CGFloat, CGFloat)], color: UIColor) {
            let path = UIBezierPath()
            path.move(to: CGPoint(x: 0, y: h))
            for (x, y) in points { path.addLine(to: CGPoint(x: x * w, y: y * h)) }
            path.addLine(to: CGPoint(x: w, y: h)); path.close()
            color.setFill(); path.fill()
        }
        ridge([(0,0.64),(0.18,0.39),(0.37,0.60),(0.62,0.43),(0.85,0.64),(1,0.50)],
              color: dark ? UIColor(red: 0.16, green: 0.32, blue: 0.39, alpha: 1) : UIColor(red: 0.43, green: 0.67, blue: 0.69, alpha: 1))
        ridge([(0,0.76),(0.24,0.64),(0.45,0.78),(0.72,0.59),(1,0.75)],
              color: dark ? UIColor(red: 0.09, green: 0.24, blue: 0.31, alpha: 1) : UIColor(red: 0.25, green: 0.53, blue: 0.56, alpha: 1))
        let lake = CGRect(x: 0, y: h * 0.82, width: w, height: h * 0.18)
        (dark ? UIColor(red: 0.12, green: 0.29, blue: 0.37, alpha: 1) : UIColor(red: 0.50, green: 0.77, blue: 0.79, alpha: 1)).setFill()
        context.fill(lake)
        context.setStrokeColor(UIColor.white.withAlphaComponent(dark ? 0.12 : 0.35).cgColor)
        context.setLineWidth(2)
        for index in 0..<5 {
            let y = h * (0.85 + CGFloat(index) * 0.027)
            context.move(to: CGPoint(x: w * (0.1 + CGFloat(index % 2) * 0.15), y: y))
            context.addLine(to: CGPoint(x: w * (0.80 + CGFloat(index % 2) * 0.1), y: y)); context.strokePath()
        }
    }
}
