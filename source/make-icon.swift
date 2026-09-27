import AppKit
let output = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let transform = NSAffineTransform(); transform.scale(by: CGFloat(pixels) / 1024); transform.concat()
        func rounded(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat, _ color: NSColor) {
            color.setFill(); NSBezierPath(roundedRect: NSRect(x: x, y: y, width: w, height: h), xRadius: r, yRadius: r).fill()
        }
        let dark = NSColor(srgbRed: 0.08, green: 0.36, blue: 0.29, alpha: 1)
        rounded(60, 60, 904, 904, 206, NSColor(srgbRed: 0.72, green: 0.91, blue: 0.82, alpha: 1))
        rounded(246, 183, 544, 628, 80, dark)
        rounded(270, 217, 496, 580, 58, NSColor(srgbRed: 0.98, green: 1, blue: 0.97, alpha: 1))
        rounded(394, 748, 236, 102, 38, dark)
        rounded(429, 782, 166, 28, 14, NSColor(srgbRed: 0.72, green: 0.91, blue: 0.82, alpha: 1))
        rounded(371, 505, 36, 58, 18, dark); rounded(619, 505, 36, 58, 18, dark)
        let smile = NSBezierPath(); smile.move(to: NSPoint(x: 443, y: 459)); smile.curve(to: NSPoint(x: 581, y: 459), controlPoint1: NSPoint(x: 468, y: 401), controlPoint2: NSPoint(x: 556, y: 401)); smile.lineWidth = 22; smile.lineCapStyle = .round; dark.setStroke(); smile.stroke()
        rounded(659, 158, 214, 214, 107, NSColor(srgbRed: 0.12, green: 0.62, blue: 0.40, alpha: 1))
        let check = NSBezierPath(); check.move(to: NSPoint(x: 710, y: 267)); check.line(to: NSPoint(x: 752, y: 226)); check.line(to: NSPoint(x: 822, y: 307)); check.lineWidth = 22; check.lineCapStyle = .round; check.lineJoinStyle = .round; NSColor.white.setStroke(); check.stroke()
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(output)/icon_\(size)x\(size)\(suffix).png"))
    }
}
