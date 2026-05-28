import AppKit

/// Draws the built-in default menu-bar glyph in code (no bundled trademarked
/// asset) and tints any image (built-in or custom local logo) to a status color.
enum GlyphRenderer {

    /// Standard menu-bar glyph size.
    static let glyphSize = NSSize(width: 18, height: 18)

    /// Produce the menu-bar image for the given status color, using a custom logo
    /// at `customLogoPath` if it exists, otherwise the built-in drawn glyph.
    static func menuBarImage(color: NSColor, customLogoPath: String?) -> NSImage {
        if let path = customLogoPath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !path.isEmpty,
           let logo = loadCustomLogo(path: path) {
            return tinted(logo, with: color, fit: glyphSize)
        }
        return defaultGlyph(color: color)
    }

    // MARK: - Built-in glyph (drawn in code)

    /// The default glyph: the Unicode character `✽` (Heavy Teardrop-Spoked
    /// Asterisk, U+273D) drawn with a system font and tinted by the status color.
    /// No bundled asset — just the glyph, kept deliberately simple.
    static let defaultGlyphCharacter = "\u{273D}" // ✽

    static func defaultGlyph(color: NSColor) -> NSImage {
        let image = NSImage(size: glyphSize, flipped: false) { rect in
            // Size the glyph to fill the menu-bar image with a touch of padding.
            let font = NSFont.systemFont(ofSize: rect.height * 0.82)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: color,
            ]
            let str = NSAttributedString(string: defaultGlyphCharacter, attributes: attrs)
            let size = str.size()
            // Center the glyph in the image rect.
            let origin = NSPoint(
                x: rect.midX - size.width / 2,
                y: rect.midY - size.height / 2)
            str.draw(at: origin)
            return true
        }
        image.isTemplate = false // rendered in actual status color, not template monochrome
        return image
    }

    // MARK: - Custom logo handling

    private static func loadCustomLogo(path: String) -> NSImage? {
        let expanded = (path as NSString).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: expanded) else { return nil }
        return NSImage(contentsOfFile: expanded)
    }

    /// Render `image` as a silhouette tinted by `color`, scaled to fit `fit`.
    /// Treats the source image's ALPHA channel as the shape: the tint color is
    /// applied only where the source is opaque, via `.sourceAtop` compositing.
    static func tinted(_ image: NSImage, with color: NSColor, fit: NSSize) -> NSImage {
        let result = NSImage(size: fit, flipped: false) { rect in
            // Aspect-fit the source into the target rect.
            let srcSize = image.size
            let scale = min(rect.width / max(srcSize.width, 1), rect.height / max(srcSize.height, 1))
            let drawSize = NSSize(width: srcSize.width * scale, height: srcSize.height * scale)
            let drawRect = NSRect(
                x: rect.midX - drawSize.width / 2,
                y: rect.midY - drawSize.height / 2,
                width: drawSize.width,
                height: drawSize.height)

            // 1. Draw the source logo (establishes the alpha silhouette).
            image.draw(in: drawRect,
                       from: .zero,
                       operation: .sourceOver,
                       fraction: 1.0)

            // 2. Paint the tint color only over opaque pixels. `.sourceAtop`
            //    keeps the destination's alpha, so transparent areas stay clear
            //    and the colored shape is recolored to the status tint.
            color.setFill()
            drawRect.fill(using: .sourceAtop)
            return true
        }
        result.isTemplate = false
        return result
    }
}
