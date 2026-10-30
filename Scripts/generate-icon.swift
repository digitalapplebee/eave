import AppKit

// Deterministic vector artwork rendered with AppKit; no downloaded assets.
let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let context = NSGraphicsContext.current!.cgContext
        context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        NSColor(srgbRed: 0.12, green: 0.13, blue: 0.14, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 52, y: 52, width: 920, height: 920), xRadius: 210, yRadius: 210).fill()
        NSColor.white.setStroke()
        let roof = NSBezierPath()
        roof.lineWidth = 48; roof.lineCapStyle = .round
        roof.move(to: NSPoint(x: 277, y: 721)); roof.line(to: NSPoint(x: 747, y: 721)); roof.stroke()
        let letter = "e" as NSString
        let font = NSFont.systemFont(ofSize: 570, weight: .medium)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
        let size = letter.size(withAttributes: attributes)
        letter.draw(at: NSPoint(x: (1024 - size.width) / 2, y: 135), withAttributes: attributes)
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        let url = destination.appendingPathComponent("icon_\(points)x\(points)\(suffix).png")
        try bitmap.representation(using: .png, properties: [:])!.write(to: url)
    }
}
