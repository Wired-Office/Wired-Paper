#!/usr/bin/env swift
// Renders the Wired Paper app icon: AppIcon.icon (Icon Composer format, with a
// Dark Mode appearance, used on macOS 26+) and the asset catalog's
// AppIcon.appiconset (the light icon, for macOS 14 and 15), plus the dark icon
// as an image set (AppIconDark) that the app shows in the Dock in Dark Mode.
// Usage: swift Scripts/generate-icon.swift [resources-directory]
//
// Design (matches LBrowser and Wired Grid): a white squircle, a dot-matrix
// page — folded corner, a heading and lines of text — and a single blue dot.
// In Dark Mode the squircle is charcoal and the ink light.

import AppKit

let resourcesDirectory = URL(fileURLWithPath: CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "WiredPaper/Resources")

struct Palette { let tile: CGColor; let border: CGColor; let ink: (r: CGFloat, g: CGFloat, b: CGFloat); let accent: CGColor }

let light = Palette(tile: CGColor(gray: 0.996, alpha: 1), border: CGColor(gray: 0, alpha: 0.10),
                    ink: (0.039, 0.039, 0.043), accent: CGColor(srgbRed: 0.184, green: 0.435, blue: 0.859, alpha: 1))
let dark = Palette(tile: CGColor(srgbRed: 0.110, green: 0.110, blue: 0.118, alpha: 1), border: CGColor(gray: 1, alpha: 0.14),
                   ink: (0.945, 0.945, 0.953), accent: CGColor(srgbRed: 0.290, green: 0.565, blue: 1.0, alpha: 1))

/// Ink density (0…1) for the dot at lattice column `c` of `columns`, row `r` of `rows`.
func density(_ c: Int, _ r: Int, _ columns: Int, _ rows: Int) -> Double {
    let x = Double(c) / Double(columns - 1), y = Double(r) / Double(rows - 1)
    // Light falls from the top left, like LBrowser's cloud.
    let light = 0.5 - 0.3 * y - 0.2 * x
    let fold = 5
    let foldStart = columns - 1 - fold
    // The top-right corner is folded over.
    if c > foldStart + r { return 0 }
    if c == foldStart + r || (r == fold && c >= foldStart) || (c == foldStart && r <= fold) { return 0.62 + light * 0.5 }
    if c > foldStart && r < fold { return 0.3 + light * 0.3 }            // the folded flap
    if c == 0 || r == 0 || c == columns - 1 || r == rows - 1 { return 0.62 + light * 0.5 }   // page edge
    // A heading, then lines of text with ragged ends.
    let lineEnds: [Int: Int] = [3: 8, 6: 12, 8: 11, 10: 12, 12: 9, 14: 12, 16: 7]
    if let end = lineEnds[r], c >= 3, c <= min(end, r < fold + 1 ? foldStart - 2 : columns - 4) {
        return r == 3 ? 0.85 + light * 0.3 : 0.5 + light * 0.4
    }
    return 0.02 + light * 0.12                                           // paper
}

/// Draws the icon on a 1024-point canvas. With `tile` the squircle is drawn too;
/// without it the page fills the canvas, which Icon Composer masks and edges itself.
func drawIcon(in ctx: CGContext, size: CGFloat, palette: Palette, tile drawsTile: Bool) {
    ctx.scaleBy(x: size / 1024, y: size / 1024)

    if drawsTile {
        let tile = CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824), cornerWidth: 185, cornerHeight: 185, transform: nil)
        ctx.addPath(tile)
        ctx.setFillColor(palette.tile)
        ctx.fillPath()
        ctx.addPath(tile)
        ctx.setStrokeColor(palette.border)
        ctx.setLineWidth(4)
        ctx.strokePath()
    } else {
        // Scale the 824-point tile's contents up to the full canvas.
        ctx.translateBy(x: 512, y: 512)
        ctx.scaleBy(x: 1024 / 824, y: 1024 / 824)
        ctx.translateBy(x: -512, y: -512)
    }

    // The dot matrix: square dots sized and shaded by density, on an exact lattice.
    let columns = 16, rows = 19
    let pitch = 22.0
    let width = pitch * Double(columns - 1)
    let originX = (1024 - width) / 2 - 20, top = 1024 - 330.0
    for r in 0..<rows {
        for c in 0..<columns {
            let h = density(c, r, columns, rows)
            guard h > 0 else { continue }
            let s = pitch * 0.66 * (0.25 + 0.75 * h)
            ctx.setFillColor(CGColor(srgbRed: palette.ink.r, green: palette.ink.g, blue: palette.ink.b, alpha: 0.2 + 0.8 * h))
            ctx.fill(CGRect(x: originX + Double(c) * pitch - s / 2, y: top - Double(r) * pitch - s / 2, width: s, height: s))
        }
    }

    ctx.setFillColor(palette.accent)
    ctx.fillEllipse(in: CGRect(x: 690, y: 700, width: 80, height: 80))
}

func renderPNG(pixels: Int, palette: Palette, tile: Bool) -> Data {
    let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    drawIcon(in: ctx, size: CGFloat(pixels), palette: palette, tile: tile)
    return NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
}

func writeJSON(_ object: [String: Any], to url: URL) throws {
    try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]).write(to: url)
}

func srgb(_ color: CGColor) -> String {
    let c = color.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil)!.components!
    let rgba = c.count == 2 ? [c[0], c[0], c[0], c[1]] : c
    return "srgb:" + rgba.map { String(format: "%.5f", Double($0)) }.joined(separator: ",")
}

// The asset catalog: the light icon at every Mac size.
struct Entry { let size: Int; let scale: Int }
let entries = [16, 32, 128, 256, 512].flatMap { [Entry(size: $0, scale: 1), Entry(size: $0, scale: 2)] }

let appIconSet = resourcesDirectory.appendingPathComponent("Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: appIconSet, withIntermediateDirectories: true)
var images: [[String: String]] = []
for entry in entries {
    let name = "icon_\(entry.size)x\(entry.size)\(entry.scale == 2 ? "@2x" : "").png"
    try renderPNG(pixels: entry.size * entry.scale, palette: light, tile: true).write(to: appIconSet.appendingPathComponent(name))
    images.append(["filename": name, "idiom": "mac", "scale": "\(entry.scale)x", "size": "\(entry.size)x\(entry.size)"])
}
try writeJSON(["images": images, "info": ["author": "xcode", "version": 1]], to: appIconSet.appendingPathComponent("Contents.json"))

// The dark icon as a plain image, for switching the Dock icon at run time
// (AppIconAppearance); macOS ignores dark appearances in an .appiconset.
let darkImageSet = resourcesDirectory.appendingPathComponent("Assets.xcassets/AppIconDark.imageset")
try FileManager.default.createDirectory(at: darkImageSet, withIntermediateDirectories: true)
var darkImages: [[String: String]] = []
for scale in [1, 2] {
    let name = "icon_dark_512x512\(scale == 2 ? "@2x" : "").png"
    try renderPNG(pixels: 512 * scale, palette: dark, tile: true).write(to: darkImageSet.appendingPathComponent(name))
    darkImages.append(["filename": name, "idiom": "mac", "scale": "\(scale)x"])
}
try writeJSON(["images": darkImages, "info": ["author": "xcode", "version": 1]], to: darkImageSet.appendingPathComponent("Contents.json"))

// The Icon Composer icon: a solid fill and one flat page layer, each with a dark specialization.
let iconBundle = resourcesDirectory.appendingPathComponent("AppIcon.icon")
let iconAssets = iconBundle.appendingPathComponent("Assets")
try FileManager.default.createDirectory(at: iconAssets, withIntermediateDirectories: true)
try renderPNG(pixels: 1024, palette: light, tile: false).write(to: iconAssets.appendingPathComponent("page.png"))
try renderPNG(pixels: 1024, palette: dark, tile: false).write(to: iconAssets.appendingPathComponent("page_dark.png"))
let layer: [String: Any] = [
    "name": "page",
    "glass": false,
    // A base "image-name" would win over the dark specialization.
    "image-name-specializations": [["value": "page.png"], ["appearance": "dark", "value": "page_dark.png"],
                                   ["appearance": "tinted", "value": "page_dark.png"]],
]
let icon: [String: Any] = [
    "fill-specializations": [["value": ["solid": srgb(light.tile)]], ["appearance": "dark", "value": ["solid": srgb(dark.tile)]]],
    "groups": [["layers": [layer], "shadow": ["kind": "none", "opacity": 0.5], "translucency": ["enabled": false, "value": 0.5]]],
    "supported-platforms": ["squares": ["macOS"]],
]
try writeJSON(icon, to: iconBundle.appendingPathComponent("icon.json"))
print("Wrote \(entries.count) icon images to \(appIconSet.path) and the light and dark icon to \(iconBundle.path)")
