#!/usr/bin/env swift
import AppKit

// Original vector artwork, rendered locally at every macOS icon size.
// All coordinates use a 1024-point design grid with its origin at bottom left.
func drawIcon() {
    let tile = NSBezierPath(roundedRect: NSRect(x: 68, y: 68, width: 888, height: 888),
                            xRadius: 198, yRadius: 198)
    NSGradient(starting: NSColor(srgbRed: 0.16, green: 0.20, blue: 0.25, alpha: 1),
               ending: NSColor(srgbRed: 0.07, green: 0.10, blue: 0.14, alpha: 1))!
        .draw(in: tile, angle: -90)

    let body = NSBezierPath()
    body.move(to: NSPoint(x: 338, y: 286))
    body.curve(to: NSPoint(x: 263, y: 417), controlPoint1: NSPoint(x: 281, y: 301),
               controlPoint2: NSPoint(x: 258, y: 349))
    body.curve(to: NSPoint(x: 302, y: 674), controlPoint1: NSPoint(x: 271, y: 506),
               controlPoint2: NSPoint(x: 271, y: 610))
    body.curve(to: NSPoint(x: 506, y: 804), controlPoint1: NSPoint(x: 336, y: 750),
               controlPoint2: NSPoint(x: 405, y: 804))
    body.curve(to: NSPoint(x: 712, y: 679), controlPoint1: NSPoint(x: 607, y: 804),
               controlPoint2: NSPoint(x: 678, y: 756))
    body.curve(to: NSPoint(x: 741, y: 441), controlPoint1: NSPoint(x: 746, y: 603),
               controlPoint2: NSPoint(x: 747, y: 520))
    body.curve(to: NSPoint(x: 637, y: 255), controlPoint1: NSPoint(x: 734, y: 356),
               controlPoint2: NSPoint(x: 708, y: 288))
    body.curve(to: NSPoint(x: 441, y: 238), controlPoint1: NSPoint(x: 580, y: 228),
               controlPoint2: NSPoint(x: 502, y: 223))
    body.curve(to: NSPoint(x: 338, y: 286), controlPoint1: NSPoint(x: 405, y: 243),
               controlPoint2: NSPoint(x: 374, y: 276))
    body.close()

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.40)
    shadow.shadowBlurRadius = 27
    shadow.shadowOffset = NSSize(width: 0, height: -19)
    shadow.set()
    NSColor(srgbRed: 0.84, green: 0.87, blue: 0.89, alpha: 1).setFill()
    body.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: NSColor(srgbRed: 0.94, green: 0.96, blue: 0.97, alpha: 1),
               ending: NSColor(srgbRed: 0.62, green: 0.69, blue: 0.74, alpha: 1))!
        .draw(in: body, angle: -70)

    let thumbRest = NSBezierPath()
    thumbRest.move(to: NSPoint(x: 303, y: 522))
    thumbRest.curve(to: NSPoint(x: 210, y: 342), controlPoint1: NSPoint(x: 264, y: 455),
                    controlPoint2: NSPoint(x: 220, y: 399))
    thumbRest.curve(to: NSPoint(x: 339, y: 286), controlPoint1: NSPoint(x: 199, y: 294),
                    controlPoint2: NSPoint(x: 275, y: 279))
    thumbRest.curve(to: NSPoint(x: 364, y: 435), controlPoint1: NSPoint(x: 351, y: 337),
                    controlPoint2: NSPoint(x: 356, y: 386))
    thumbRest.close()
    NSColor(srgbRed: 0.49, green: 0.57, blue: 0.63, alpha: 1).setFill()
    thumbRest.fill()

    let split = NSBezierPath()
    split.move(to: NSPoint(x: 507, y: 798))
    split.line(to: NSPoint(x: 507, y: 542))
    split.lineWidth = 9
    split.lineCapStyle = .round
    NSColor(srgbRed: 0.25, green: 0.33, blue: 0.39, alpha: 1).setStroke()
    split.stroke()

    let wheelSocket = NSBezierPath(roundedRect: NSRect(x: 466, y: 613, width: 82, height: 148),
                                   xRadius: 39, yRadius: 39)
    NSColor(srgbRed: 0.16, green: 0.23, blue: 0.29, alpha: 1).setFill()
    wheelSocket.fill()
    let wheel = NSBezierPath(roundedRect: NSRect(x: 480, y: 629, width: 54, height: 116),
                             xRadius: 25, yRadius: 25)
    NSGradient(starting: NSColor(srgbRed: 0.51, green: 0.93, blue: 0.91, alpha: 1),
               ending: NSColor(srgbRed: 0.20, green: 0.67, blue: 0.72, alpha: 1))!
        .draw(in: wheel, angle: 0)
    NSColor(srgbRed: 0.10, green: 0.43, blue: 0.48, alpha: 0.7).setStroke()
    for y in stride(from: 650, through: 723, by: 17) {
        let groove = NSBezierPath()
        groove.move(to: NSPoint(x: 488, y: y))
        groove.line(to: NSPoint(x: 526, y: y))
        groove.lineWidth = 3
        groove.stroke()
    }

    let thumbWheel = NSBezierPath(roundedRect: NSRect(x: 302, y: 501, width: 62, height: 24),
                                  xRadius: 12, yRadius: 12)
    NSColor(srgbRed: 0.18, green: 0.25, blue: 0.30, alpha: 1).setFill()
    thumbWheel.fill()
    let modeButton = NSBezierPath(roundedRect: NSRect(x: 489, y: 505, width: 36, height: 17),
                                  xRadius: 8, yRadius: 8)
    modeButton.fill()
}

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: make-icon.swift <output.iconset>\n", stderr)
    exit(1)
}
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
do {
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    for points in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            let pixels = points * scale
            guard let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                isPlanar: false, colorSpaceName: .deviceRGB,
                bytesPerRow: 0, bitsPerPixel: 0
            ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
                throw NSError(domain: "MXMasterManager.Icon", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "Could not create icon canvas"])
            }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            context.cgContext.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
            drawIcon()
            context.flushGraphics()
            NSGraphicsContext.restoreGraphicsState()
            let suffix = scale == 2 ? "@2x" : ""
            let name = "icon_\(points)x\(points)\(suffix).png"
            guard let data = bitmap.representation(using: .png, properties: [:]) else {
                throw NSError(domain: "MXMasterManager.Icon", code: 2,
                              userInfo: [NSLocalizedDescriptionKey: "Could not encode icon PNG"])
            }
            try data.write(to: output.appendingPathComponent(name), options: .atomic)
        }
    }
    print("Rendered original icon: \(output.path)")
} catch {
    fputs("Icon generation failed: \(error.localizedDescription)\n", stderr)
    exit(1)
}
