// Renders the installer disk image background: the app's dark backdrop, a title, and a glowing arrow
// from the FreeClean icon to the Applications shortcut.
// Usage: swift scripts/make-dmg-background.swift <out-dir>   (writes background.png and background@2x.png)
// Layout must match scripts/bundle.sh: a 660-wide window, icons centred at (170, 215) and (490, 215).
// The artwork is 480 tall but everything important sits in the top ~410pt, so it still fits when the
// viewer's Finder shows a tab bar (which shortens the window's content area).
import AppKit

let outDir = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "build")
let W: CGFloat = 660, H: CGFloat = 480
let appIcon = CGPoint(x: 170, y: 215), appsIcon = CGPoint(x: 490, y: 215)

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r, green: g, blue: b, alpha: a)
}

func render(scale: CGFloat) -> Data {
    let px = Int(W * scale), py = Int(H * scale)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: py, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: W, height: H)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    // Work in Finder's coordinates: origin top-left, y down.
    ctx.translateBy(x: 0, y: H)
    ctx.scaleBy(x: 1, y: -1)
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    func gradient(_ c: [CGColor]) -> CGGradient { CGGradient(colorsSpace: space, colors: c as CFArray, locations: nil)! }

    // Backdrop: deep navy/violet with soft colour glows, like the app.
    ctx.drawLinearGradient(gradient([rgb(0.09, 0.07, 0.2), rgb(0.05, 0.05, 0.12)]),
                           start: .zero, end: CGPoint(x: 0, y: H), options: [])
    for (c, r, col) in [(CGPoint(x: 90, y: 60), 300.0, rgb(0.62, 0.13, 0.45, 0.45)),
                        (CGPoint(x: 600, y: 380), 320.0, rgb(0.05, 0.33, 0.45, 0.45)),
                        (CGPoint(x: 560, y: 40), 240.0, rgb(0.33, 0.2, 0.7, 0.35))] {
        ctx.drawRadialGradient(gradient([col, col.copy(alpha: 0)!]), startCenter: c, startRadius: 0,
                               endCenter: c, endRadius: r, options: [])
    }

    // Faint sparkles.
    var seed: UInt64 = 7
    func rand() -> CGFloat { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return CGFloat(seed >> 33) / CGFloat(1 << 31) }
    for _ in 0..<38 {
        let p = CGPoint(x: rand() * W, y: rand() * H), r = 0.6 + rand() * 1.3
        ctx.setFillColor(rgb(1, 1, 1, 0.15 + rand() * 0.35))
        ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
    }

    // Soft glass plates behind each icon, tall enough to hold the icon and its label.
    for c in [appIcon, appsIcon] {
        let plate = CGPath(roundedRect: CGRect(x: c.x - 96, y: c.y - 90, width: 192, height: 210),
                           cornerWidth: 36, cornerHeight: 36, transform: nil)
        ctx.addPath(plate); ctx.setFillColor(rgb(1, 1, 1, 0.05)); ctx.fillPath()
        ctx.addPath(plate); ctx.setStrokeColor(rgb(1, 1, 1, 0.1)); ctx.setLineWidth(1); ctx.strokePath()
        // Light chip behind the file name: Finder draws icon labels in black on a background picture,
        // so they need a light backing to stay readable.
        let chip = CGPath(roundedRect: CGRect(x: c.x - 62, y: c.y + 74, width: 124, height: 24),
                          cornerWidth: 12, cornerHeight: 12, transform: nil)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: 2), blur: 8, color: rgb(0, 0, 0, 0.35))
        ctx.addPath(chip); ctx.setFillColor(rgb(0.93, 0.92, 0.97, 0.92)); ctx.fillPath()
        ctx.restoreGState()
    }

    // Glowing curved arrow between the icons: one smooth curve that ends in a filled head pointing
    // along the curve's final direction.
    let start = CGPoint(x: appIcon.x + 104, y: appIcon.y + 6)
    let tip = CGPoint(x: appsIcon.x - 104, y: appIcon.y + 6)
    let control = CGPoint(x: (start.x + tip.x) / 2, y: start.y - 64)
    // Direction of travel at the tip of a quadratic curve is (tip - control).
    let dx = tip.x - control.x, dy = tip.y - control.y, len = (dx * dx + dy * dy).squareRoot()
    let dir = CGPoint(x: dx / len, y: dy / len), perp = CGPoint(x: -dir.y, y: dir.x)
    let headLength: CGFloat = 22, headHalfWidth: CGFloat = 14
    // The shaft stops where the head begins, so the two join cleanly.
    let shaftEnd = CGPoint(x: tip.x - dir.x * headLength * 0.8, y: tip.y - dir.y * headLength * 0.8)
    let shaft = CGMutablePath()
    shaft.move(to: start)
    shaft.addQuadCurve(to: shaftEnd, control: control)
    let shaftShape = shaft.copy(strokingWithWidth: 5, lineCap: .round, lineJoin: .round, miterLimit: 1, transform: .identity)
    let base = CGPoint(x: tip.x - dir.x * headLength, y: tip.y - dir.y * headLength)
    let head = CGMutablePath()
    head.move(to: tip)
    head.addLine(to: CGPoint(x: base.x + perp.x * headHalfWidth, y: base.y + perp.y * headHalfWidth))
    head.addLine(to: CGPoint(x: base.x - perp.x * headHalfWidth, y: base.y - perp.y * headHalfWidth))
    head.closeSubpath()
    // Round off the head's corners a little.
    let headShape = head.copy(strokingWithWidth: 4, lineCap: .round, lineJoin: .round, miterLimit: 1, transform: .identity)
    // Paint the three pieces separately (combining them into one path would let opposite windings cancel
    // and hollow out the head), then lay the gradient over the merged shape.
    func fillArrow(_ color: CGColor) {
        ctx.setFillColor(color)
        for piece in [shaftShape, head as CGPath, headShape] { ctx.addPath(piece); ctx.fillPath() }
    }
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 16, color: rgb(0.85, 0.45, 1, 0.9))
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    fillArrow(rgb(0.8, 0.48, 1))
    ctx.endTransparencyLayer()
    ctx.restoreGState()
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    fillArrow(rgb(1, 1, 1))
    ctx.setBlendMode(.sourceIn)
    ctx.drawLinearGradient(gradient([rgb(1, 0.45, 0.7), rgb(0.6, 0.45, 1)]), start: start, end: tip,
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.endTransparencyLayer()

    // Text (drawn in a flipped context, so draw via NSString with a flipped graphics context).
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
    func text(_ s: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, y: CGFloat) {
        let font = NSFont.systemFont(ofSize: size, weight: weight)
        let attr: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let str = NSAttributedString(string: s, attributes: attr)
        str.draw(at: CGPoint(x: (W - str.size().width) / 2, y: y))
    }
    text("Install FreeClean", size: 26, weight: .bold, color: .white, y: 34)
    text("Drag the app onto the Applications folder", size: 14, weight: .medium,
         color: NSColor.white.withAlphaComponent(0.75), y: 70)
    text("First launch: right-click FreeClean → Open", size: 11.5, weight: .medium,
         color: NSColor.white.withAlphaComponent(0.6), y: 368)

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

try! FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
try! render(scale: 1).write(to: outDir.appendingPathComponent("background.png"))
try! render(scale: 2).write(to: outDir.appendingPathComponent("background@2x.png"))
print("Wrote background.png and background@2x.png to \(outDir.path)")
