import AppKit

// Draws the app icon into an .iconset folder: a warm red rounded square
// holding a soft white disc, echoing the menu bar circle.
// Usage: swift make_icon.swift OUTPUT.iconset

let output = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func render(_ pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let scale = CGFloat(pixels) / 1024
    NSGraphicsContext.current!.cgContext.scaleBy(x: scale, y: scale)

    // macOS icon grid: 824pt body centred on a 1024pt canvas.
    let body = NSRect(x: 100, y: 100, width: 824, height: 824)
    let shape = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.shadowBlurRadius = 20
    shadow.set()
    NSColor(srgbRed: 0.85, green: 0.15, blue: 0.24, alpha: 1).setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(
        starting: NSColor(srgbRed: 1.0, green: 0.42, blue: 0.36, alpha: 1),
        ending: NSColor(srgbRed: 0.80, green: 0.11, blue: 0.24, alpha: 1))!
        .draw(in: shape, angle: -90)

    let center = NSPoint(x: 512, y: 512)
    func disc(_ radius: CGFloat) -> NSBezierPath {
        NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    }
    NSColor.white.withAlphaComponent(0.14).setFill()
    disc(300).fill()
    NSColor.white.withAlphaComponent(0.22).setFill()
    disc(240).fill()
    NSColor.white.setFill()
    disc(170).fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for size in [16, 32, 128, 256, 512] {
    try render(size).write(to: output.appendingPathComponent("icon_\(size)x\(size).png"))
    try render(size * 2).write(to: output.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
