#!/usr/bin/env swift
//
// make-icon.swift — generate StatusGlance.app's bundle icon entirely in code.
//
// Draws the `✽` glyph (U+273D, the same mark the menu bar uses) on the app's
// dark-navy palette and composes a multi-resolution AppIcon.icns. No bundled or
// third-party art, and nothing resembling any other brand's logo — our own glyph,
// our own colors. Run from the repo root: `swift scripts/make-icon.swift` (or `make icon`).
//
import AppKit
import Foundation

let glyph = "\u{273D}" // ✽ Heavy Teardrop-Spoked Asterisk
let bgColor = NSColor(srgbRed: 0x0F / 255.0, green: 0x14 / 255.0, blue: 0x20 / 255.0, alpha: 1) // Palette.background
let fgColor = NSColor(srgbRed: 0x3F / 255.0, green: 0xB9 / 255.0, blue: 0x50 / 255.0, alpha: 1) // StatusColor.green

func renderPNG(pixels: Int) -> Data {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { fatalError("could not allocate bitmap at \(pixels)px") }
    rep.size = NSSize(width: pixels, height: pixels)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let size = CGFloat(pixels)
    let rect = NSRect(x: 0, y: 0, width: size, height: size)

    // Rounded-square plate with a slight inset (macOS icons are not full-bleed).
    let inset = size * 0.06
    let plate = rect.insetBy(dx: inset, dy: inset)
    let radius = plate.width * 0.225
    bgColor.setFill()
    NSBezierPath(roundedRect: plate, xRadius: radius, yRadius: radius).fill()

    // Centered glyph.
    let font = NSFont.systemFont(ofSize: size * 0.6, weight: .regular)
    let str = NSAttributedString(string: glyph, attributes: [.font: font, .foregroundColor: fgColor])
    let strSize = str.size()
    str.draw(at: NSPoint(x: rect.midX - strSize.width / 2, y: rect.midY - strSize.height / 2))

    NSGraphicsContext.restoreGraphicsState()

    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("PNG encode failed at \(pixels)px")
    }
    return data
}

let fm = FileManager.default
let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)
let iconset = cwd.appendingPathComponent("AppIcon.iconset")
try? fm.removeItem(at: iconset)
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)

let variants: [(name: String, px: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for v in variants {
    try renderPNG(pixels: v.px).write(to: iconset.appendingPathComponent("\(v.name).png"))
}

let resourcesDir = cwd.appendingPathComponent("Resources")
try? fm.createDirectory(at: resourcesDir, withIntermediateDirectories: true)
let icns = resourcesDir.appendingPathComponent("AppIcon.icns")

let proc = Process()
proc.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
proc.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
try proc.run()
proc.waitUntilExit()
try? fm.removeItem(at: iconset)

if proc.terminationStatus == 0 {
    print("Wrote \(icns.path)")
} else {
    FileHandle.standardError.write("iconutil failed (\(proc.terminationStatus))\n".data(using: .utf8)!)
}
exit(proc.terminationStatus)
