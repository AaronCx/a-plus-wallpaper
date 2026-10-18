// make-spike-icon.swift: draws the Phase 0 spike's app icon (original work).
//
// Usage: DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
//          xcrun swift scripts/make-spike-icon.swift OUTPUT.png
//
// TestFlight rejects uploads without an app icon, so the spike needs one to
// reach a device without a cable. It is a 1024 x 1024 opaque PNG: a dark
// gradient, a few soft colour fields (a nod to the spike's drifting noise) and
// "a+" in the rounded system font. Everything is drawn here; no artwork is
// copied. The output is deterministic, so re-running it gives the same pixels.
import AppKit
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers

let size = 1024
guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: make-spike-icon.swift OUTPUT.png\n".utf8))
    exit(64)
}
let output = URL(fileURLWithPath: CommandLine.arguments[1])

let space = CGColorSpace(name: CGColorSpace.sRGB)!
// noneSkipLast: App Store icons must have no alpha channel.
guard let context = CGContext(
    data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
    space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
) else { fatalError("could not create the bitmap context") }

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [r, g, b, a])!
}

let full = CGRect(x: 0, y: 0, width: size, height: size)

// Background: deep indigo at the top to near-black at the bottom.
let background = CGGradient(
    colorsSpace: space,
    colors: [color(0.13, 0.10, 0.32), color(0.03, 0.03, 0.08)] as CFArray,
    locations: [0, 1]
)!
context.drawLinearGradient(
    background, start: CGPoint(x: 0, y: CGFloat(size)), end: .zero, options: []
)

// Soft colour fields: radial gradients that fade to transparent.
let fields: [(x: CGFloat, y: CGFloat, radius: CGFloat, color: CGColor)] = [
    (0.22, 0.78, 0.55, color(0.98, 0.36, 0.55, 0.85)),
    (0.82, 0.62, 0.50, color(0.30, 0.55, 1.00, 0.80)),
    (0.55, 0.18, 0.60, color(0.20, 0.90, 0.75, 0.55)),
]
for field in fields {
    let center = CGPoint(x: field.x * CGFloat(size), y: field.y * CGFloat(size))
    let gradient = CGGradient(
        colorsSpace: space,
        colors: [field.color, field.color.copy(alpha: 0)!] as CFArray,
        locations: [0, 1]
    )!
    context.drawRadialGradient(
        gradient, startCenter: center, startRadius: 0,
        endCenter: center, endRadius: field.radius * CGFloat(size), options: []
    )
}

// "a+" centred, in the rounded heavy system font.
let base = NSFont.systemFont(ofSize: 430, weight: .heavy)
let font = base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: 430) } ?? base
let text = NSAttributedString(string: "a+", attributes: [
    .font: font,
    .foregroundColor: NSColor(cgColor: color(1, 1, 1))!,
    .kern: -12,
])
let line = CTLineCreateWithAttributedString(text)
let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
context.textPosition = CGPoint(
    x: (CGFloat(size) - bounds.width) / 2 - bounds.minX,
    y: (CGFloat(size) - bounds.height) / 2 - bounds.minY
)
context.setShadow(offset: CGSize(width: 0, height: -10), blur: 30, color: color(0, 0, 0, 0.35))
CTLineDraw(line, context)

guard let image = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil)
else { fatalError("could not encode the PNG") }
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("could not write \(output.path)") }
print("wrote \(output.path) (\(size) x \(size), no alpha)")
