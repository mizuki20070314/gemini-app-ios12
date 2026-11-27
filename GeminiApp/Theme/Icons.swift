import UIKit

enum IconName: String {
    case menu
    case newChat
    case plus
    case send
    case stop
    case search
    case close
    case chevronRight
    case chevronDown
    case chevronUp
    case copy
    case retry
    case star
    case starFill
    case settings
    case trash
    case pencil
    case share
    case chat
    case image
    case camera
    case file
    case globe
    case thinking
    case check
    case more
    case sparkle
    case refresh
    case key
    case user
    case download
    case wand
}

enum Icons {
    private static var cache: [String: UIImage] = [:]

    static func image(_ name: IconName, size: CGFloat = 20, color: UIColor) -> UIImage {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        let key = "\(name.rawValue)_\(Int(size * 10))_\(Int(r*255))_\(Int(g*255))_\(Int(b*255))_\(Int(a*255))"
        if let cached = cache[key] { return cached }

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        let img = renderer.image { ctx in
            let cg = ctx.cgContext
            cg.setStrokeColor(color.cgColor)
            cg.setFillColor(color.cgColor)
            cg.setLineCap(.round)
            cg.setLineJoin(.round)
            let s = size
            let lw = max(1.5, s * 0.09)
            cg.setLineWidth(lw)

            switch name {
            case .menu:
                for y in [s * 0.27, s * 0.50, s * 0.73] {
                    cg.move(to: CGPoint(x: s * 0.15, y: y))
                    cg.addLine(to: CGPoint(x: s * 0.85, y: y))
                }
                cg.strokePath()

            case .newChat, .pencil:
                let p = UIBezierPath()
                p.move(to: CGPoint(x: s * 0.65, y: s * 0.16))
                p.addLine(to: CGPoint(x: s * 0.84, y: s * 0.35))
                p.addLine(to: CGPoint(x: s * 0.35, y: s * 0.84))
                p.addLine(to: CGPoint(x: s * 0.16, y: s * 0.84))
                p.addLine(to: CGPoint(x: s * 0.16, y: s * 0.65))
                p.close()
                p.lineWidth = lw
                p.stroke()

            case .plus:
                cg.move(to: CGPoint(x: s * 0.5, y: s * 0.18))
                cg.addLine(to: CGPoint(x: s * 0.5, y: s * 0.82))
                cg.move(to: CGPoint(x: s * 0.18, y: s * 0.5))
                cg.addLine(to: CGPoint(x: s * 0.82, y: s * 0.5))
                cg.strokePath()

            case .send:
                cg.move(to: CGPoint(x: s * 0.5, y: s * 0.80))
                cg.addLine(to: CGPoint(x: s * 0.5, y: s * 0.22))
                cg.move(to: CGPoint(x: s * 0.25, y: s * 0.45))
                cg.addLine(to: CGPoint(x: s * 0.5, y: s * 0.20))
                cg.addLine(to: CGPoint(x: s * 0.75, y: s * 0.45))
                cg.strokePath()

            case .stop:
                let rect = CGRect(x: s * 0.26, y: s * 0.26, width: s * 0.48, height: s * 0.48)
                UIBezierPath(roundedRect: rect, cornerRadius: s * 0.10).fill()

            case .search:
                let circle = UIBezierPath(ovalIn: CGRect(x: s * 0.16, y: s * 0.16, width: s * 0.52, height: s * 0.52))
                circle.lineWidth = lw
                circle.stroke()
                cg.move(to: CGPoint(x: s * 0.61, y: s * 0.61))
                cg.addLine(to: CGPoint(x: s * 0.84, y: s * 0.84))
                cg.strokePath()

            case .close:
                cg.move(to: CGPoint(x: s * 0.22, y: s * 0.22))
                cg.addLine(to: CGPoint(x: s * 0.78, y: s * 0.78))
                cg.move(to: CGPoint(x: s * 0.78, y: s * 0.22))
                cg.addLine(to: CGPoint(x: s * 0.22, y: s * 0.78))
                cg.strokePath()

            case .chevronRight:
                cg.move(to: CGPoint(x: s * 0.36, y: s * 0.22))
                cg.addLine(to: CGPoint(x: s * 0.66, y: s * 0.50))
                cg.addLine(to: CGPoint(x: s * 0.36, y: s * 0.78))
                cg.strokePath()

            case .chevronDown:
                cg.move(to: CGPoint(x: s * 0.22, y: s * 0.36))
                cg.addLine(to: CGPoint(x: s * 0.50, y: s * 0.66))
                cg.addLine(to: CGPoint(x: s * 0.78, y: s * 0.36))
                cg.strokePath()

            case .chevronUp:
                cg.move(to: CGPoint(x: s * 0.22, y: s * 0.64))
                cg.addLine(to: CGPoint(x: s * 0.50, y: s * 0.34))
                cg.addLine(to: CGPoint(x: s * 0.78, y: s * 0.64))
                cg.strokePath()

            case .copy:
                let back = UIBezierPath(roundedRect: CGRect(x: s * 0.18, y: s * 0.16, width: s * 0.46, height: s * 0.52), cornerRadius: s * 0.08)
                back.lineWidth = lw * 0.9
                back.stroke()
                let front = UIBezierPath(roundedRect: CGRect(x: s * 0.36, y: s * 0.32, width: s * 0.46, height: s * 0.52), cornerRadius: s * 0.08)
                front.lineWidth = lw * 0.9
                front.stroke()

            case .retry, .refresh:
                let arc = UIBezierPath(arcCenter: CGPoint(x: s * 0.5, y: s * 0.5), radius: s * 0.32, startAngle: -0.35, endAngle: CGFloat.pi * 1.45, clockwise: true)
                arc.lineWidth = lw
                arc.stroke()
                cg.move(to: CGPoint(x: s * 0.78, y: s * 0.20))
                cg.addLine(to: CGPoint(x: s * 0.80, y: s * 0.42))
                cg.addLine(to: CGPoint(x: s * 0.58, y: s * 0.40))
                cg.strokePath()

            case .star, .starFill:
                let path = UIBezierPath()
                let cx = s * 0.5, cy = s * 0.52
                let rOut = s * 0.38, rIn = s * 0.16
                for i in 0..<10 {
                    let angle = CGFloat(i) * CGFloat.pi / 5.0 - CGFloat.pi / 2.0
                    let r = (i % 2 == 0) ? rOut : rIn
                    let pt = CGPoint(x: cx + cos(angle) * r, y: cy + sin(angle) * r)
                    if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
                }
                path.close()
                path.lineWidth = lw * 0.9
                if name == .starFill { path.fill() } else { path.stroke() }

            case .settings:
                let c = CGPoint(x: s * 0.5, y: s * 0.5)
                let inner = UIBezierPath(ovalIn: CGRect(x: s * 0.36, y: s * 0.36, width: s * 0.28, height: s * 0.28))
                inner.lineWidth = lw
                inner.stroke()
                let outer = UIBezierPath(ovalIn: CGRect(x: s * 0.21, y: s * 0.21, width: s * 0.58, height: s * 0.58))
                outer.lineWidth = lw * 0.85
                outer.stroke()
                for i in 0..<8 {
                    let a = CGFloat(i) * CGFloat.pi / 4.0
                    cg.move(to: CGPoint(x: c.x + cos(a) * s * 0.30, y: c.y + sin(a) * s * 0.30))
                    cg.addLine(to: CGPoint(x: c.x + cos(a) * s * 0.42, y: c.y + sin(a) * s * 0.42))
                }
                cg.strokePath()

            case .trash:
                cg.move(to: CGPoint(x: s * 0.18, y: s * 0.26))
                cg.addLine(to: CGPoint(x: s * 0.82, y: s * 0.26))
                cg.move(to: CGPoint(x: s * 0.38, y: s * 0.16))
                cg.addLine(to: CGPoint(x: s * 0.62, y: s * 0.16))
                cg.strokePath()
                let bin = UIBezierPath(roundedRect: CGRect(x: s * 0.26, y: s * 0.26, width: s * 0.48, height: s * 0.58), cornerRadius: s * 0.06)
                bin.lineWidth = lw
                bin.stroke()

            case .share:
                let box = UIBezierPath()
                box.move(to: CGPoint(x: s * 0.22, y: s * 0.48))
                box.addLine(to: CGPoint(x: s * 0.22, y: s * 0.82))
                box.addLine(to: CGPoint(x: s * 0.78, y: s * 0.82))
                box.addLine(to: CGPoint(x: s * 0.78, y: s * 0.48))
                box.lineWidth = lw
                box.stroke()
                cg.move(to: CGPoint(x: s * 0.5, y: s * 0.60))
                cg.addLine(to: CGPoint(x: s * 0.5, y: s * 0.16))
                cg.move(to: CGPoint(x: s * 0.32, y: s * 0.34))
                cg.addLine(to: CGPoint(x: s * 0.5, y: s * 0.16))
                cg.addLine(to: CGPoint(x: s * 0.68, y: s * 0.34))
                cg.strokePath()

            case .chat:
                let b = UIBezierPath(roundedRect: CGRect(x: s * 0.15, y: s * 0.18, width: s * 0.70, height: s * 0.52), cornerRadius: s * 0.12)
                b.lineWidth = lw
                b.stroke()
                cg.move(to: CGPoint(x: s * 0.30, y: s * 0.70))
                cg.addLine(to: CGPoint(x: s * 0.22, y: s * 0.86))
                cg.addLine(to: CGPoint(x: s * 0.46, y: s * 0.70))
                cg.strokePath()

            case .image:
                let frame = UIBezierPath(roundedRect: CGRect(x: s * 0.14, y: s * 0.18, width: s * 0.72, height: s * 0.64), cornerRadius: s * 0.10)
                frame.lineWidth = lw
                frame.stroke()
                let sun = UIBezierPath(ovalIn: CGRect(x: s * 0.28, y: s * 0.30, width: s * 0.13, height: s * 0.13))
                sun.fill()
                cg.move(to: CGPoint(x: s * 0.20, y: s * 0.74))
                cg.addLine(to: CGPoint(x: s * 0.44, y: s * 0.48))
                cg.addLine(to: CGPoint(x: s * 0.60, y: s * 0.62))
                cg.addLine(to: CGPoint(x: s * 0.70, y: s * 0.52))
                cg.addLine(to: CGPoint(x: s * 0.82, y: s * 0.74))
                cg.strokePath()

            case .camera:
                let body = UIBezierPath(roundedRect: CGRect(x: s * 0.14, y: s * 0.28, width: s * 0.72, height: s * 0.54), cornerRadius: s * 0.10)
                body.lineWidth = lw
                body.stroke()
                let lens = UIBezierPath(ovalIn: CGRect(x: s * 0.36, y: s * 0.41, width: s * 0.28, height: s * 0.28))
                lens.lineWidth = lw
                lens.stroke()
                cg.move(to: CGPoint(x: s * 0.34, y: s * 0.28))
                cg.addLine(to: CGPoint(x: s * 0.40, y: s * 0.18))
                cg.addLine(to: CGPoint(x: s * 0.60, y: s * 0.18))
                cg.addLine(to: CGPoint(x: s * 0.66, y: s * 0.28))
                cg.strokePath()

            case .file:
                let p = UIBezierPath()
                p.move(to: CGPoint(x: s * 0.24, y: s * 0.14))
                p.addLine(to: CGPoint(x: s * 0.58, y: s * 0.14))
                p.addLine(to: CGPoint(x: s * 0.76, y: s * 0.32))
                p.addLine(to: CGPoint(x: s * 0.76, y: s * 0.86))
                p.addLine(to: CGPoint(x: s * 0.24, y: s * 0.86))
                p.close()
                p.lineWidth = lw
                p.stroke()

            case .globe:
                let c = UIBezierPath(ovalIn: CGRect(x: s * 0.15, y: s * 0.15, width: s * 0.70, height: s * 0.70))
                c.lineWidth = lw
                c.stroke()
                let v = UIBezierPath(ovalIn: CGRect(x: s * 0.34, y: s * 0.15, width: s * 0.32, height: s * 0.70))
                v.lineWidth = lw * 0.8
                v.stroke()
                cg.move(to: CGPoint(x: s * 0.16, y: s * 0.50))
                cg.addLine(to: CGPoint(x: s * 0.84, y: s * 0.50))
                cg.strokePath()

            case .thinking:
                let bulb = UIBezierPath(arcCenter: CGPoint(x: s * 0.5, y: s * 0.42), radius: s * 0.26, startAngle: 0.5, endAngle: CGFloat.pi - 0.5, clockwise: false)
                bulb.lineWidth = lw
                bulb.stroke()
                cg.move(to: CGPoint(x: s * 0.38, y: s * 0.68))
                cg.addLine(to: CGPoint(x: s * 0.62, y: s * 0.68))
                cg.move(to: CGPoint(x: s * 0.41, y: s * 0.80))
                cg.addLine(to: CGPoint(x: s * 0.59, y: s * 0.80))
                cg.strokePath()

            case .check:
                cg.move(to: CGPoint(x: s * 0.20, y: s * 0.52))
                cg.addLine(to: CGPoint(x: s * 0.42, y: s * 0.74))
                cg.addLine(to: CGPoint(x: s * 0.82, y: s * 0.28))
                cg.strokePath()

            case .more:
                for x in [s * 0.24, s * 0.50, s * 0.76] {
                    UIBezierPath(ovalIn: CGRect(x: x - s * 0.07, y: s * 0.43, width: s * 0.14, height: s * 0.14)).fill()
                }

            case .sparkle, .wand:
                let path = GeminiSparkView.sparkPath(in: CGRect(x: s * 0.10, y: s * 0.10, width: s * 0.80, height: s * 0.80))
                path.fill()

            case .key:
                let ring = UIBezierPath(ovalIn: CGRect(x: s * 0.16, y: s * 0.34, width: s * 0.32, height: s * 0.32))
                ring.lineWidth = lw
                ring.stroke()
                cg.move(to: CGPoint(x: s * 0.48, y: s * 0.50))
                cg.addLine(to: CGPoint(x: s * 0.84, y: s * 0.50))
                cg.move(to: CGPoint(x: s * 0.70, y: s * 0.50))
                cg.addLine(to: CGPoint(x: s * 0.70, y: s * 0.64))
                cg.move(to: CGPoint(x: s * 0.82, y: s * 0.50))
                cg.addLine(to: CGPoint(x: s * 0.82, y: s * 0.62))
                cg.strokePath()

            case .user:
                let head = UIBezierPath(ovalIn: CGRect(x: s * 0.34, y: s * 0.16, width: s * 0.32, height: s * 0.32))
                head.lineWidth = lw
                head.stroke()
                let arc = UIBezierPath(arcCenter: CGPoint(x: s * 0.5, y: s * 0.88), radius: s * 0.32, startAngle: CGFloat.pi * 1.12, endAngle: CGFloat.pi * 1.88, clockwise: true)
                arc.lineWidth = lw
                arc.stroke()

            case .download:
                cg.move(to: CGPoint(x: s * 0.5, y: s * 0.18))
                cg.addLine(to: CGPoint(x: s * 0.5, y: s * 0.68))
                cg.move(to: CGPoint(x: s * 0.30, y: s * 0.50))
                cg.addLine(to: CGPoint(x: s * 0.5, y: s * 0.70))
                cg.addLine(to: CGPoint(x: s * 0.70, y: s * 0.50))
                cg.move(to: CGPoint(x: s * 0.20, y: s * 0.82))
                cg.addLine(to: CGPoint(x: s * 0.80, y: s * 0.82))
                cg.strokePath()
            }
        }
        if cache.count > 120 { cache.removeAll() }
        cache[key] = img
        return img
    }
}

/// Gemini 4-point gradient sparkle view with smooth pulse/rotate streaming animation
final class GeminiSparkView: UIView {
    private let gradientLayer = CAGradientLayer()
    private let maskLayer = CAShapeLayer()
    private var isPulsing = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = .clear
        gradientLayer.colors = [
            UIColor(hex: "#4285F4").cgColor,
            UIColor(hex: "#9B72CB").cgColor,
            UIColor(hex: "#D96570").cgColor
        ]
        gradientLayer.startPoint = CGPoint(x: 0, y: 0)
        gradientLayer.endPoint = CGPoint(x: 1, y: 1)
        gradientLayer.mask = maskLayer
        layer.addSublayer(gradientLayer)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = bounds
        maskLayer.frame = bounds
        maskLayer.path = GeminiSparkView.sparkPath(in: bounds).cgPath
    }

    static func sparkPath(in rect: CGRect) -> UIBezierPath {
        let p = UIBezierPath()
        let cx = rect.midX
        let cy = rect.midY
        let rx = rect.width * 0.5
        let ry = rect.height * 0.5
        let c: CGFloat = 0.14
        p.move(to: CGPoint(x: cx, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: cy), controlPoint: CGPoint(x: cx + rx * c, y: cy - ry * c))
        p.addQuadCurve(to: CGPoint(x: cx, y: rect.maxY), controlPoint: CGPoint(x: cx + rx * c, y: cy + ry * c))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: cy), controlPoint: CGPoint(x: cx - rx * c, y: cy + ry * c))
        p.addQuadCurve(to: CGPoint(x: cx, y: rect.minY), controlPoint: CGPoint(x: cx - rx * c, y: cy - ry * c))
        p.close()
        return p
    }

    func startPulsing() {
        guard !isPulsing else { return }
        isPulsing = true
        let rot = CABasicAnimation(keyPath: "transform.rotation.z")
        rot.fromValue = 0
        rot.toValue = CGFloat.pi * 2
        rot.duration = 2.4
        rot.repeatCount = .infinity
        layer.add(rot, forKey: "gemini_spin")

        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.88
        scale.toValue = 1.08
        scale.duration = 0.8
        scale.autoreverses = true
        scale.repeatCount = .infinity
        layer.add(scale, forKey: "gemini_pulse")
    }

    func stopPulsing() {
        isPulsing = false
        layer.removeAnimation(forKey: "gemini_spin")
        layer.removeAnimation(forKey: "gemini_pulse")
    }
}
