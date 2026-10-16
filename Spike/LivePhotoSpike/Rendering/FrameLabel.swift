import CoreGraphics
import CoreText
import CoreVideo
import Foundation

/// Burns a small variant label into a rendered frame, so a tester looking at a
/// Lock Screen can tell which of the variants they set as the wallpaper.
/// Debug-only spike behaviour; it is drawn identically into the still and into
/// every video frame.
enum FrameLabel {
    static func draw(_ text: String, into pixelBuffer: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard let context = CGContext(
            data: base, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer), space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return }

        let shortEdge = CGFloat(min(width, height))
        let font = CTFontCreateUIFontForLanguage(.system, shortEdge * 0.038, nil)
            ?? CTFontCreateWithName("Helvetica" as CFString, shortEdge * 0.038, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: 0.9),
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)

        // Lower third, clear of the Lock Screen clock and the bottom controls.
        let origin = CGPoint(x: (CGFloat(width) - bounds.width) / 2, y: CGFloat(height) * 0.28)
        let padding = shortEdge * 0.02
        let pill = CGRect(
            x: origin.x - padding, y: origin.y - padding,
            width: bounds.width + 2 * padding, height: bounds.height + 2 * padding)
        context.setFillColor(CGColor(gray: 0, alpha: 0.35))
        context.addPath(CGPath(roundedRect: pill, cornerWidth: pill.height / 2, cornerHeight: pill.height / 2, transform: nil))
        context.fillPath()

        context.textPosition = CGPoint(x: origin.x - bounds.minX, y: origin.y - bounds.minY)
        CTLineDraw(line, context)
    }
}
