import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("usage: render_app_icon.swift <output.png>\n", stderr)
    exit(2)
}

let canvasSize = NSSize(width: 1024, height: 1024)
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: 1024,
    pixelsHigh: 1024,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fputs("failed to create bitmap\n", stderr)
    exit(1)
}

NSGraphicsContext.saveGraphicsState()
guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fputs("failed to create graphics context\n", stderr)
    exit(1)
}
NSGraphicsContext.current = context
context.imageInterpolation = NSImageInterpolation.high

NSColor.clear.setFill()
NSBezierPath(rect: NSRect(origin: .zero, size: canvasSize)).fill()

let tileRect = NSRect(x: 64, y: 64, width: 896, height: 896)
let tilePath = NSBezierPath(roundedRect: tileRect, xRadius: 210, yRadius: 210)
NSColor(srgbRed: 0.118, green: 0.133, blue: 0.145, alpha: 1).setFill()
tilePath.fill()

let insetPath = NSBezierPath(roundedRect: tileRect.insetBy(dx: 10, dy: 10), xRadius: 200, yRadius: 200)
insetPath.lineWidth = 5
NSColor.white.withAlphaComponent(0.08).setStroke()
insetPath.stroke()

let braceFont = NSFont.monospacedSystemFont(ofSize: 430, weight: .medium)
let braceAttributes: [NSAttributedString.Key: Any] = [
    .font: braceFont,
    .foregroundColor: NSColor(srgbRed: 0.93, green: 0.95, blue: 0.96, alpha: 1)
]

func drawCentered(_ text: String, in rect: NSRect) {
    let string = NSAttributedString(string: text, attributes: braceAttributes)
    let size = string.size()
    string.draw(at: NSPoint(
        x: rect.midX - size.width / 2,
        y: rect.midY - size.height / 2
    ))
}

drawCentered("{", in: NSRect(x: 126, y: 172, width: 260, height: 680))
drawCentered("}", in: NSRect(x: 638, y: 172, width: 260, height: 680))

let lightColors = [
    NSColor(srgbRed: 1.00, green: 0.26, blue: 0.31, alpha: 1),
    NSColor(srgbRed: 1.00, green: 0.72, blue: 0.08, alpha: 1),
    NSColor(srgbRed: 0.14, green: 0.79, blue: 0.36, alpha: 1)
]
let lightCenters: [CGFloat] = [690, 512, 334]

for (color, centerY) in zip(lightColors, lightCenters) {
    let outerRect = NSRect(x: 438, y: centerY - 74, width: 148, height: 148)
    NSColor.black.withAlphaComponent(0.22).setFill()
    NSBezierPath(ovalIn: outerRect.insetBy(dx: -8, dy: -8)).fill()

    color.setFill()
    NSBezierPath(ovalIn: outerRect).fill()

    let highlightRect = NSRect(x: 468, y: centerY + 17, width: 60, height: 28)
    NSColor.white.withAlphaComponent(0.30).setFill()
    NSBezierPath(ovalIn: highlightRect).fill()
}

context.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: NSBitmapImageRep.FileType.png, properties: [:]) else {
    fputs("failed to encode PNG\n", stderr)
    exit(1)
}
try png.write(
    to: URL(fileURLWithPath: CommandLine.arguments[1]),
    options: Data.WritingOptions.atomic
)
