import AppKit
import Foundation

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSGraphicsContext.current?.cgContext.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        let background = NSBezierPath(roundedRect: NSRect(x: 46, y: 46, width: 932, height: 932), xRadius: 214, yRadius: 214)
        NSGradient(starting: NSColor(white: 0.19, alpha: 1), ending: NSColor(white: 0.045, alpha: 1))!.draw(in: background, angle: -70)
        let island = NSBezierPath(roundedRect: NSRect(x: 176, y: 260, width: 672, height: 480), xRadius: 132, yRadius: 132)
        NSColor(calibratedRed: 0.72, green: 0.91, blue: 0.67, alpha: 1).setFill(); island.fill()
        NSColor.black.setFill()
        NSBezierPath(roundedRect: NSRect(x: 352, y: 562, width: 320, height: 210), xRadius: 72, yRadius: 72).fill()
        NSBezierPath(roundedRect: NSRect(x: 254, y: 360, width: 88, height: 98), xRadius: 27, yRadius: 27).fill()
        for (index, height) in [56.0, 94.0, 124.0, 77.0].enumerated() {
            NSBezierPath(roundedRect: NSRect(x: 628 + Double(index) * 30, y: 406 - height / 2, width: 14, height: height), xRadius: 7, yRadius: 7).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
