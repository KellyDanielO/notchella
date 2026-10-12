import AppKit

// Renders the Notch app icon at 1024×1024 following the macOS icon grid (824pt body, ~185 corner radius).
let size: CGFloat = 1024
let output = CommandLine.arguments[1]

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

// Body
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let bodyPath = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)

// Soft drop shadow under the body.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor.black.withAlphaComponent(0.35).cgColor)
color(0x000000).setFill()
bodyPath.fill()
ctx.restoreGState()

ctx.saveGState()
bodyPath.addClip()
// Vibrant diagonal gradient: indigo → violet → warm peach.
NSGradient(colors: [color(0x4F3DF5), color(0x9B4DE0), color(0xF0628C), color(0xFFB36B)],
           atLocations: [0, 0.4, 0.75, 1], colorSpace: .sRGB)!
    .draw(in: body, angle: -55)
// Soft light from the top, like a screen glow.
NSGradient(colors: [NSColor.white.withAlphaComponent(0.22), NSColor.white.withAlphaComponent(0)])!
    .draw(in: CGRect(x: body.minX, y: body.midY, width: body.width, height: body.height / 2), angle: -90)

// The notch: concave flares at the top, rounded bottom corners.
let notchWidth: CGFloat = 400, notchHeight: CGFloat = 210, flare: CGFloat = 34, corner: CGFloat = 78
let top = body.maxY, left = body.midX - notchWidth / 2 - flare, right = body.midX + notchWidth / 2 + flare
let notch = NSBezierPath()
notch.move(to: CGPoint(x: left, y: top))
notch.curve(to: CGPoint(x: left + flare, y: top - flare), controlPoint1: CGPoint(x: left + flare * 0.55, y: top), controlPoint2: CGPoint(x: left + flare, y: top - flare * 0.45))
notch.line(to: CGPoint(x: left + flare, y: top - notchHeight + corner))
notch.curve(to: CGPoint(x: left + flare + corner, y: top - notchHeight), controlPoint1: CGPoint(x: left + flare, y: top - notchHeight + corner * 0.45), controlPoint2: CGPoint(x: left + flare + corner * 0.45, y: top - notchHeight))
notch.line(to: CGPoint(x: right - flare - corner, y: top - notchHeight))
notch.curve(to: CGPoint(x: right - flare, y: top - notchHeight + corner), controlPoint1: CGPoint(x: right - flare - corner * 0.45, y: top - notchHeight), controlPoint2: CGPoint(x: right - flare, y: top - notchHeight + corner * 0.45))
notch.line(to: CGPoint(x: right - flare, y: top - flare))
notch.curve(to: CGPoint(x: right, y: top), controlPoint1: CGPoint(x: right - flare, y: top - flare * 0.45), controlPoint2: CGPoint(x: right - flare * 0.55, y: top))
notch.close()

ctx.saveGState()
ctx.clip(to: CGRect(x: body.minX, y: body.minY, width: body.width, height: body.height - 2))
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 34, color: NSColor.black.withAlphaComponent(0.4).cgColor)
color(0x050505).setFill()
notch.fill()
ctx.restoreGState()
color(0x050505).setFill()
notch.fill()

// Live activity inside the notch: album art on the left, waveform on the right.
let rowY = top - notchHeight / 2 - 20
let art = CGRect(x: body.midX - 150, y: rowY - 45, width: 90, height: 90)
ctx.saveGState()
NSBezierPath(roundedRect: art, xRadius: 22, yRadius: 22).addClip()
NSGradient(colors: [color(0xFFB36B), color(0xF0628C), color(0x9B4DE0)])!.draw(in: art, angle: -45)
ctx.restoreGState()

let barHeights: [CGFloat] = [46, 86, 60, 100, 52]
for (index, height) in barHeights.enumerated() {
    let x = body.midX + 30 + CGFloat(index) * 26
    let bar = CGRect(x: x, y: rowY - height / 2, width: 14, height: height)
    color(0x7CF2C8).setFill()
    NSBezierPath(roundedRect: bar, xRadius: 7, yRadius: 7).fill()
}

// Faint rim so the edge reads on dark backgrounds.
ctx.restoreGState()
NSColor.white.withAlphaComponent(0.18).setStroke()
let rim = NSBezierPath(roundedRect: body.insetBy(dx: 1.5, dy: 1.5), xRadius: 184, yRadius: 184)
rim.lineWidth = 3
rim.stroke()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
