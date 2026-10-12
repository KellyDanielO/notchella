import AppKit
import SwiftUI

extension NSImage {
    /// The artwork's most vivid colour, brightened so it stays readable on the black notch.
    ///
    /// An average of the whole image turns busy or dark covers into muddy brown or grey, so this
    /// samples a small grid and picks the most saturated, reasonably bright colour. Covers with no
    /// real colour (black and white, greyscale) get plain white.
    var notchAccentColor: Color? {
        guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }

        let side = 12
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: side,
                height: side,
                bitsPerComponent: 8,
                bytesPerRow: side * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return nil }

        var best: (hue: CGFloat, saturation: CGFloat, brightness: CGFloat, score: CGFloat)?
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let color = NSColor(
                srgbRed: CGFloat(pixels[index]) / 255,
                green: CGFloat(pixels[index + 1]) / 255,
                blue: CGFloat(pixels[index + 2]) / 255,
                alpha: 1
            )
            var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
            color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
            // Near-black pixels have unreliable hue; skip them.
            guard brightness > 0.2 else { continue }
            let score = saturation * (0.4 + 0.6 * brightness)
            if score > (best?.score ?? 0) {
                best = (hue, saturation, brightness, score)
            }
        }

        guard let best, best.saturation > 0.18 else { return .white }
        return Color(
            hue: best.hue,
            saturation: min(max(best.saturation, 0.5), 0.85),
            brightness: max(best.brightness, 0.9)
        )
    }
}
