#!/usr/bin/env swift
import AppKit

// Package the checked-in dithered master image at every macOS icon resolution.
// A small transparent inset matches the standard macOS icon tile footprint.
guard CommandLine.arguments.count == 3 else {
    fputs("Usage: make-icon.swift <source.png> <output.iconset>\n", stderr)
    exit(1)
}
let source = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
do {
    guard let image = NSImage(contentsOf: source) else {
        throw NSError(domain: "MXMasterManager.Icon", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "Could not read icon master: \(source.path)"])
    }
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
                throw NSError(domain: "MXMasterManager.Icon", code: 2,
                              userInfo: [NSLocalizedDescriptionKey: "Could not create icon canvas"])
            }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            context.cgContext.clear(CGRect(x: 0, y: 0, width: pixels, height: pixels))
            context.imageInterpolation = .high
            let inset = CGFloat(pixels) * 44 / 1024
            image.draw(in: NSRect(x: inset, y: inset,
                                 width: CGFloat(pixels) - inset * 2,
                                 height: CGFloat(pixels) - inset * 2),
                       from: .zero, operation: .sourceOver, fraction: 1)
            context.flushGraphics()
            NSGraphicsContext.restoreGraphicsState()
            let suffix = scale == 2 ? "@2x" : ""
            guard let data = bitmap.representation(using: .png, properties: [:]) else {
                throw NSError(domain: "MXMasterManager.Icon", code: 3,
                              userInfo: [NSLocalizedDescriptionKey: "Could not encode icon PNG"])
            }
            try data.write(to: output.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"), options: .atomic)
        }
    }
    print("Packaged dithered mouse icon: \(output.path)")
} catch {
    fputs("Icon generation failed: \(error.localizedDescription)\n", stderr)
    exit(1)
}
