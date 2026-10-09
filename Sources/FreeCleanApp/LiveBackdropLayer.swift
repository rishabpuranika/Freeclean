import AppKit
import SwiftUI

/// The animated backdrop, built from Core Animation layers.
///
/// All motion (drifting color blobs, rising sparkles) is described once as CAAnimations / a CAEmitterLayer
/// and then run by the system render server, so the app itself does almost no work per frame.
/// (The previous SwiftUI TimelineView version re-rendered every frame and cost ~25% CPU while idle.)
struct LiveBackground: NSViewRepresentable {
    let screen: Screen
    /// Below 1, the backdrop becomes a translucent color wash over the window's behind-window blur.
    var tint: Double = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeNSView(context: Context) -> BackdropView {
        let v = BackdropView()
        v.setTint(tint)
        v.apply(colors: screen.backdrop, animated: false, reduceMotion: reduceMotion)
        return v
    }

    func updateNSView(_ v: BackdropView, context: Context) {
        v.setTint(tint)
        v.apply(colors: screen.backdrop, animated: true, reduceMotion: reduceMotion)
    }
}

final class BackdropView: NSView {
    private let base = CALayer()
    private var blobs: [CAGradientLayer] = []
    private let sparkles = CAEmitterLayer()
    private let vignette = CAGradientLayer()
    private var colors: [Color] = []
    private var reduceMotion = false
    private var animatedSize: CGSize = .zero

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer = CALayer()
        layer?.addSublayer(base)
        base.backgroundColor = NSColor(red: 0.05, green: 0.04, blue: 0.1, alpha: 1).cgColor
        for _ in 0..<4 {
            let blob = CAGradientLayer()
            blob.type = .radial
            blob.startPoint = CGPoint(x: 0.5, y: 0.5)
            blob.endPoint = CGPoint(x: 1, y: 1)
            layer?.addSublayer(blob)
            blobs.append(blob)
        }
        configureSparkles()
        layer?.addSublayer(sparkles)
        vignette.type = .radial
        vignette.startPoint = CGPoint(x: 0.5, y: 0.5)
        vignette.endPoint = CGPoint(x: 1.15, y: 1.15)
        vignette.colors = [NSColor.clear.cgColor, NSColor.black.withAlphaComponent(0.5).cgColor]
        vignette.locations = [0.45, 1]
        layer?.addSublayer(vignette)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// Full strength paints an opaque backdrop; lower values drop the solid base so whatever is
    /// behind (the desktop blur) shows through, tinted by the drifting colors.
    func setTint(_ t: Double) {
        let translucent = t < 1
        base.isHidden = translucent
        vignette.isHidden = translucent
        layer?.opacity = Float(t)
    }

    func apply(colors new: [Color], animated: Bool, reduceMotion rm: Bool) {
        let motionChanged = rm != reduceMotion
        reduceMotion = rm
        if new != colors {
            colors = new
            CATransaction.begin()
            CATransaction.setAnimationDuration(animated ? 0.9 : 0)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
            for (i, blob) in blobs.enumerated() {
                let c = NSColor(new[i % new.count])
                blob.colors = [c.withAlphaComponent(0.95).cgColor, c.withAlphaComponent(0.45).cgColor,
                               c.withAlphaComponent(0).cgColor]
                blob.locations = [0, 0.45, 1]
            }
            CATransaction.commit()
        }
        if motionChanged { animatedSize = .zero; needsLayout = true }
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        base.frame = bounds
        vignette.frame = bounds
        sparkles.frame = bounds
        sparkles.emitterPosition = CGPoint(x: bounds.midX, y: -10)
        sparkles.emitterSize = CGSize(width: bounds.width * 1.1, height: 1)
        // Each blob is ~1.1x the window, anchored around a different corner.
        let anchors: [CGPoint] = [.init(x: 0.15, y: 0.85), .init(x: 0.85, y: 0.8), .init(x: 0.2, y: 0.15), .init(x: 0.85, y: 0.2)]
        let d = max(bounds.width, bounds.height) * 1.1
        for (i, blob) in blobs.enumerated() {
            blob.bounds = CGRect(x: 0, y: 0, width: d, height: d)
            blob.position = CGPoint(x: bounds.width * anchors[i].x, y: bounds.height * anchors[i].y)
        }
        CATransaction.commit()
        if bounds.size != animatedSize {
            animatedSize = bounds.size
            startMotion()
        }
    }

    private func startMotion() {
        for blob in blobs { blob.removeAllAnimations() }
        sparkles.birthRate = reduceMotion ? 0 : 1
        guard !reduceMotion, bounds.width > 0 else { return }
        let w = bounds.width, h = bounds.height
        let drifts: [CGSize] = [.init(width: 0.22, height: -0.18), .init(width: -0.2, height: -0.22),
                                .init(width: 0.25, height: 0.2), .init(width: -0.22, height: 0.18)]
        for (i, blob) in blobs.enumerated() {
            let move = CABasicAnimation(keyPath: "transform.translation")
            move.fromValue = NSValue(size: .zero)
            move.toValue = NSValue(size: CGSize(width: w * drifts[i].width, height: h * drifts[i].height))
            move.duration = 16 + Double(i) * 5
            move.autoreverses = true
            move.repeatCount = .infinity
            move.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            move.beginTime = CACurrentMediaTime() - Double(i) * 3
            blob.add(move, forKey: "drift")

            let breathe = CABasicAnimation(keyPath: "transform.scale")
            breathe.fromValue = 0.9
            breathe.toValue = 1.12
            breathe.duration = 11 + Double(i) * 3
            breathe.autoreverses = true
            breathe.repeatCount = .infinity
            breathe.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            blob.add(breathe, forKey: "breathe")
        }
    }

    private func configureSparkles() {
        sparkles.emitterShape = .line
        sparkles.renderMode = .additive
        let cell = CAEmitterCell()
        cell.contents = Self.dot
        cell.birthRate = 2.2
        cell.lifetime = 40
        cell.velocity = 14
        cell.velocityRange = 9
        cell.emissionLongitude = .pi / 2 // upward (layer y grows up on macOS)
        cell.emissionRange = .pi / 10
        cell.xAcceleration = 0
        cell.scale = 0.22
        cell.scaleRange = 0.14
        cell.alphaRange = 0.5
        cell.alphaSpeed = -0.012
        cell.color = NSColor.white.withAlphaComponent(0.8).cgColor
        sparkles.emitterCells = [cell]
        // Pre-fill the window so sparkles are already scattered at launch.
        sparkles.beginTime = CACurrentMediaTime() - 40
    }

    /// Soft round dot used as the sparkle texture.
    private static let dot: CGImage? = {
        let size = 24
        guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let colors = [CGColor(gray: 1, alpha: 1), CGColor(gray: 1, alpha: 0.35), CGColor(gray: 1, alpha: 0)] as CFArray
        let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.35, 1])!
        let c = CGPoint(x: size / 2, y: size / 2)
        ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: CGFloat(size) / 2, options: [])
        return ctx.makeImage()
    }()
}

/// The orb's rotating light ring and breathing glow, as render-server animations (no per-frame app work).
struct OrbAura: NSViewRepresentable {
    let screen: Screen
    let busy: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeNSView(context: Context) -> OrbAuraView { OrbAuraView() }

    func updateNSView(_ v: OrbAuraView, context: Context) {
        v.update(colors: screen.colors, busy: busy, reduceMotion: reduceMotion)
    }
}

final class OrbAuraView: NSView {
    private let glow = CAGradientLayer()
    private let ring = CAGradientLayer()
    private let ringMask = CAShapeLayer()
    private var state: (colors: [Color], busy: Bool, reduceMotion: Bool)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer = CALayer()
        glow.type = .radial
        glow.startPoint = CGPoint(x: 0.5, y: 0.5)
        glow.endPoint = CGPoint(x: 1, y: 1)
        ring.type = .conic
        ring.startPoint = CGPoint(x: 0.5, y: 0.5)
        ring.endPoint = CGPoint(x: 0.5, y: 0)
        ringMask.fillColor = nil
        ringMask.strokeColor = NSColor.white.cgColor
        ring.mask = ringMask
        layer?.addSublayer(glow)
        layer?.addSublayer(ring)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        glow.frame = bounds
        let d: CGFloat = 196
        ring.bounds = CGRect(x: 0, y: 0, width: d, height: d)
        ring.position = CGPoint(x: bounds.midX, y: bounds.midY)
        ringMask.frame = ring.bounds
        let lw = (state?.busy ?? false) ? 4.0 : 2.5
        ringMask.lineWidth = lw
        ringMask.path = CGPath(ellipseIn: ring.bounds.insetBy(dx: lw / 2, dy: lw / 2), transform: nil)
        CATransaction.commit()
    }

    func update(colors: [Color], busy: Bool, reduceMotion: Bool) {
        if let s = state, s.colors == colors, s.busy == busy, s.reduceMotion == reduceMotion { return }
        state = (colors, busy, reduceMotion)
        let c0 = NSColor(colors[0]), c1 = NSColor(colors[1])
        glow.colors = [c1.withAlphaComponent(0.55).cgColor, c1.withAlphaComponent(0.25).cgColor, c1.withAlphaComponent(0).cgColor]
        glow.locations = [0.45, 0.7, 1]
        ring.colors = [c0.cgColor, NSColor.white.withAlphaComponent(0.9).cgColor, c1.cgColor,
                       c0.withAlphaComponent(0.1).cgColor, c0.cgColor]
        needsLayout = true

        ring.removeAllAnimations()
        glow.removeAllAnimations()
        guard !reduceMotion else { return }
        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = 0
        spin.toValue = -2 * Double.pi
        spin.duration = busy ? 1.6 : 14
        spin.repeatCount = .infinity
        ring.add(spin, forKey: "spin")

        let breathe = CABasicAnimation(keyPath: "transform.scale")
        breathe.fromValue = 0.97
        breathe.toValue = 1.06
        breathe.duration = busy ? 0.9 : 2.4
        breathe.autoreverses = true
        breathe.repeatCount = .infinity
        breathe.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        glow.add(breathe, forKey: "breathe")
    }
}
