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

    static func image(symbol: String, mode: EnergyMode, appearance: NSAppearance) -> NSImage? {
        guard let base = NSImage(systemSymbolName:symbol,accessibilityDescription:nil) else { return nil }
        let image: NSImage
        if mode != .unknown,
           let colored = base.withSymbolConfiguration(.init(paletteColors:[color(for:mode,appearance:appearance)])) {
            // Template status images are recolored by AppKit, so preserve the mode's original color.
            image = colored
            image.isTemplate = false
        } else {
            image = base
            image.isTemplate = true
        }
        image.size = NSSize(width:18,height:10)
        return image
    }
}
