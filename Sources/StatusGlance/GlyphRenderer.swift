import AppKit

/// Draws the menu-bar glyph entirely in code — the `✽` character tinted by the
/// current status color. No bundled assets, no user-supplied images.
enum GlyphRenderer {

    /// Standard menu-bar glyph size.
    static let glyphSize = NSSize(width: 18, height: 18)

    /// Produce the menu-bar image for the given status color.
    static func menuBarImage(color: NSColor) -> NSImage {
        defaultGlyph(color: color)
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
}
