import AppKit
import PowerCore

enum MenuBarStyle {
    static func color(for mode: EnergyMode, appearance: NSAppearance) -> NSColor {
        let semanticColor: NSColor
        switch mode {
        case .automatic: semanticColor = .systemBlue
        case .lowPower: semanticColor = .systemGreen
        case .highPower: semanticColor = .systemOrange
        case .unknown: semanticColor = .labelColor
        }
        var resolved = semanticColor
        appearance.performAsCurrentDrawingAppearance {
            resolved = semanticColor.usingColorSpace(.sRGB) ?? semanticColor
        }
        return resolved
    }

    static func image(percent: Int?, isCharging: Bool, isFull: Bool = false, mode: EnergyMode, appearance: NSAppearance) -> NSImage? {
        let size = NSSize(width:18,height:10)
        let image = NSImage(size:size)
        let validPercent = percent.flatMap { (0...100).contains($0) ? $0 : nil }
        let ink = mode == .unknown ? NSColor.black : color(for:mode,appearance:appearance)
        // Keep both bitmap scales at the same point size so small strokes stay sharp on Retina displays.
        for scale in [1, 2] {
            guard let bitmap = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:18*scale,pixelsHigh:10*scale,
                                               bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,
                                               colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0),
                  let context = NSGraphicsContext(bitmapImageRep:bitmap) else { continue }
            bitmap.size = size
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            context.cgContext.scaleBy(x:CGFloat(scale),y:CGFloat(scale))
            context.cgContext.clear(CGRect(origin:.zero,size:size))
            drawBattery(percent:validPercent,isCharging:isCharging,isFull:isFull,ink:ink)
            NSGraphicsContext.restoreGraphicsState()
            image.addRepresentation(bitmap)
        }
        guard !image.representations.isEmpty else { return nil }
        // Unknown modes use the system's template tint; known modes preserve their original colors.
        image.isTemplate = mode == .unknown
        return image
    }

    private static func drawBattery(percent: Int?, isCharging: Bool, isFull: Bool, ink: NSColor) {
        ink.setStroke(); ink.setFill()
        let outline = NSBezierPath(roundedRect:NSRect(x:0.5,y:0.5,width:15.5,height:9),xRadius:1.6,yRadius:1.6)
        outline.lineWidth = 1
        outline.stroke()
        NSBezierPath(roundedRect:NSRect(x:16.75,y:3,width:1.25,height:4),xRadius:0.6,yRadius:0.6).fill()

        guard let percent else {
            ("?" as NSString).draw(at:NSPoint(x:6.25,y:0.75),withAttributes:[
                .font:NSFont.systemFont(ofSize:7,weight:.bold), .foregroundColor:ink
            ])
            return
        }
        let interior = NSRect(x:2,y:2,width:12.5,height:6)
        // Fill width follows the actual percentage, including while charging; no 25% buckets.
        let width = interior.width*CGFloat(percent)/100
        if width > 0 {
            NSBezierPath(roundedRect:NSRect(x:interior.minX,y:interior.minY,width:width,height:interior.height),
                         xRadius:min(0.9,width/2),yRadius:0.9).fill()
        }

        if isFull {
            // A transparent inset mark preserves the mode color and works on either menu-bar appearance.
            let check = NSImage(systemSymbolName:"checkmark",accessibilityDescription:nil)?
                .withSymbolConfiguration(.init(pointSize:7,weight:.bold))
            check?.draw(in:NSRect(x:5.3,y:3.1,width:6,height:4),from:.zero,operation:.destinationOut,fraction:1)
        } else if isCharging {
            let bolt = NSBezierPath()
            bolt.move(to:NSPoint(x:9,y:8.1))
            for point in [NSPoint(x:6.5,y:4.8), NSPoint(x:8.05,y:4.8), NSPoint(x:7.4,y:1.9),
                          NSPoint(x:10.05,y:5.7), NSPoint(x:8.5,y:5.7)] { bolt.line(to:point) }
            bolt.close()
            // Cut a transparent halo in this bitmap so the bolt is visible over filled and empty areas.
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current?.cgContext.setBlendMode(.clear)
            bolt.lineWidth = 1.35; bolt.lineJoinStyle = .round
            bolt.stroke()
            NSGraphicsContext.restoreGraphicsState()
            ink.setFill(); bolt.fill()
        }
    }
}
