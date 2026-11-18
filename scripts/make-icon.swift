import AppKit

// Draws the app icon at 1024 pt and writes Resources/AppIcon.icns through iconutil.
let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
    let body = NSRect(x: 100, y: 100, width: 824, height: 824)
    let shape = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)

    NSGraphicsContext.current?.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = 28
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.set()
    NSColor.black.setFill()
    shape.fill()
    NSGraphicsContext.current?.restoreGraphicsState()

    NSGradient(colors: [
        NSColor(red: 0.16, green: 0.36, blue: 0.98, alpha: 1),
        NSColor(red: 0.47, green: 0.25, blue: 0.93, alpha: 1),
    ])!.draw(in: shape, angle: -55)

    let selection = NSRect(x: 230, y: 400, width: 420, height: 320)
    NSColor.white.withAlphaComponent(0.16).setFill()
    NSBezierPath(rect: selection).fill()

    let dashed = NSBezierPath(rect: selection)
    dashed.lineWidth = 14
    dashed.setLineDash([42, 26], count: 2, phase: 0)
    NSColor.white.withAlphaComponent(0.95).setStroke()
    dashed.stroke()

    let corner: CGFloat = 70
    let brackets = NSBezierPath()
    brackets.lineWidth = 30
    brackets.lineCapStyle = .round
    brackets.lineJoinStyle = .round
    for (x, y, dx, dy) in [(selection.minX, selection.maxY, 1.0, -1.0), (selection.maxX, selection.maxY, -1.0, -1.0),
                           (selection.minX, selection.minY, 1.0, 1.0)] {
        brackets.move(to: NSPoint(x: x, y: y + dy * corner))
        brackets.line(to: NSPoint(x: x, y: y))
        brackets.line(to: NSPoint(x: x + dx * corner, y: y))
    }
    NSColor.white.setStroke()
    brackets.stroke()

    let tip = NSPoint(x: selection.maxX - 6, y: selection.minY + 6)
    let arrow = NSBezierPath()
    let points: [(CGFloat, CGFloat)] = [(0, 0), (0, -250), (62, -192), (108, -292), (152, -272), (108, -176), (190, -176)]
    arrow.move(to: NSPoint(x: tip.x + points[0].0, y: tip.y + points[0].1))
    for p in points.dropFirst() { arrow.line(to: NSPoint(x: tip.x + p.0 * 0.8, y: tip.y + p.1 * 0.8)) }
    arrow.close()
    arrow.lineJoinStyle = .round
    arrow.lineWidth = 20
    NSColor(white: 0.08, alpha: 1).setStroke()
    arrow.stroke()
    NSColor.white.setFill()
    arrow.fill()
    return true
}

let root = URL(fileURLWithPath: CommandLine.arguments[1])
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = base * scale
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
        NSGraphicsContext.restoreGraphicsState()
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try rep.representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(name))
    }
}
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("Resources/AppIcon.icns").path]
try task.run()
task.waitUntilExit()
try? FileManager.default.removeItem(at: root.appendingPathComponent("docs/icon.png"))
try FileManager.default.copyItem(at: iconset.appendingPathComponent("icon_128x128@2x.png"), to: root.appendingPathComponent("docs/icon.png"))
