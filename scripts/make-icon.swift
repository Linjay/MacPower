import AppKit
import Foundation

// Build the app's existing SF Symbol mark at each native icon size. No runtime image dependency.
let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let width = CGFloat(pixels)
        let rect = NSRect(x: width * 0.09, y: width * 0.09, width: width * 0.82, height: width * 0.82)
        let shape = NSBezierPath(roundedRect: rect, xRadius: width * 0.19, yRadius: width * 0.19)
        NSGradient(starting: NSColor(srgbRed: 0.20, green: 0.42, blue: 0.81, alpha: 1),
                   ending: NSColor(srgbRed: 0.45, green: 0.64, blue: 1, alpha: 1))!.draw(in: shape, angle: 90)
        let symbol = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil)!
            .withSymbolConfiguration(.init(pointSize: width * 0.56, weight: .semibold))!
            .withSymbolConfiguration(.init(paletteColors: [.white]))!
        let height = width * 0.61
        let symbolWidth = height * symbol.size.width / symbol.size.height
        let symbolRect = NSRect(x: (width - symbolWidth) / 2, y: (width - height) / 2,
                                width: symbolWidth, height: height)
        symbol.draw(in: symbolRect)
        NSGraphicsContext.restoreGraphicsState()
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent(name))
    }
}
