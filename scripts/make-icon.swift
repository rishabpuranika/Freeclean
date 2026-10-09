// Renders the FreeClean app icon ("Disk Ring": coloured usage ring with a check, on a dark squircle)
// into an .icns. Usage: swift scripts/make-icon.swift <output.icns> [preview.png]
import AppKit

let args = CommandLine.arguments.dropFirst()
let out = args.first ?? "build/AppIcon.icns"
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("FreeClean.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r, green: g, blue: b, alpha: a)
}

/// Ring segments as (start, end) boundaries in degrees (clockwise from 12 o'clock) and top/bottom gradient
/// colours, echoing the Disk Usage chart. Each arc is shortened by its round cap so segments never touch.
let segments: [(CGFloat, CGFloat, CGColor, CGColor)] = [
    (0, 150, rgb(0.42, 0.72, 1.0), rgb(0.2, 0.5, 0.98)),       // blue
    (150, 262, rgb(0.92, 0.45, 1.0), rgb(0.72, 0.25, 0.92)),   // purple
    (262, 318, rgb(1.0, 0.5, 0.6), rgb(0.95, 0.3, 0.45)),      // pink
    (318, 360, rgb(0.72, 0.72, 0.78), rgb(0.55, 0.55, 0.62)),  // grey
]

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let s = CGFloat(px)
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    func gradient(_ colors: [CGColor], _ locs: [CGFloat]? = nil) -> CGGradient {
        CGGradient(colorsSpace: space, colors: colors as CFArray, locations: locs)!
    }

    // Apple's icon grid: the shape fills ~80% of the canvas, leaving room for the shadow.
    let inset = s * 0.1
    let rect = CGRect(x: inset, y: inset * 1.15, width: s - inset * 2, height: s - inset * 2)
    let squircle = CGPath(roundedRect: rect, cornerWidth: rect.width * 0.225, cornerHeight: rect.width * 0.225, transform: nil)
    let center = CGPoint(x: rect.midX, y: rect.midY)

    // Drop shadow.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.03, color: rgb(0, 0, 0, 0.35))
    ctx.addPath(squircle); ctx.setFillColor(rgb(0, 0, 0)); ctx.fillPath()
    ctx.restoreGState()

    // Dark body with a faint violet glow in the middle.
    ctx.saveGState()
    ctx.addPath(squircle); ctx.clip()
    ctx.drawLinearGradient(gradient([rgb(0.13, 0.15, 0.27), rgb(0.05, 0.06, 0.12)]),
                           start: CGPoint(x: 0, y: rect.maxY), end: CGPoint(x: 0, y: rect.minY), options: [])
    ctx.drawRadialGradient(gradient([rgb(0.45, 0.35, 0.95, 0.35), rgb(0.45, 0.35, 0.95, 0)]),
                           startCenter: center, startRadius: 0, endCenter: center, endRadius: rect.width * 0.45, options: [])
    ctx.restoreGState()

    // Ring segments, each filled with its own vertical gradient and a soft glow.
    let radius = rect.width * 0.265
    let width = rect.width * 0.095
    // Angle taken up by a round cap, plus a small visible gap.
    let capDegrees = (width / 2) / radius * 180 / .pi + 1.5
    for (a, b, top, bottom) in segments {
        // Convert "degrees clockwise from 12 o'clock" to Core Graphics angles.
        let start = (90 - (a + capDegrees)) * .pi / 180, end = (90 - (b - capDegrees)) * .pi / 180
        let arc = CGMutablePath()
        arc.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: true)
        let stroked = arc.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 1)
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: s * 0.035, color: bottom.copy(alpha: 0.55))
        ctx.addPath(stroked); ctx.setFillColor(bottom); ctx.fillPath()
        ctx.restoreGState()
        ctx.saveGState()
        ctx.addPath(stroked); ctx.clip()
        ctx.drawLinearGradient(gradient([top, bottom]), start: CGPoint(x: 0, y: center.y + radius + width),
                               end: CGPoint(x: 0, y: center.y - radius - width), options: [])
        ctx.restoreGState()
    }

    // Green check in the middle, with a glow.
    let check = CGMutablePath()
    let c = rect.width * 0.11
    check.move(to: CGPoint(x: center.x - c, y: center.y + c * 0.02))
    check.addLine(to: CGPoint(x: center.x - c * 0.25, y: center.y - c * 0.72))
    check.addLine(to: CGPoint(x: center.x + c * 1.05, y: center.y + c * 0.78))
    let checkStroke = check.copy(strokingWithWidth: rect.width * 0.06, lineCap: .round, lineJoin: .round, miterLimit: 1)
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: s * 0.04, color: rgb(0.3, 1, 0.6, 0.7))
    ctx.addPath(checkStroke); ctx.setFillColor(rgb(0.35, 0.95, 0.62)); ctx.fillPath()
    ctx.restoreGState()

    // Glossy top edge.
    ctx.saveGState()
    ctx.addPath(squircle); ctx.clip()
    ctx.drawLinearGradient(gradient([rgb(1, 1, 1, 0.16), rgb(1, 1, 1, 0)]), start: CGPoint(x: 0, y: rect.maxY),
                           end: CGPoint(x: 0, y: rect.midY + rect.height * 0.1), options: [])
    ctx.restoreGState()
    ctx.addPath(squircle)
    ctx.setStrokeColor(rgb(1, 1, 1, 0.1)); ctx.setLineWidth(max(1, s * 0.003)); ctx.strokePath()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", out]
try! p.run()
p.waitUntilExit()
if let preview = args.dropFirst().first { try! render(1024).write(to: URL(fileURLWithPath: preview)) }

print("Wrote \(out)")
