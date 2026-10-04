#!/usr/bin/env swift
// Renders the Wired Paper app icon into the asset catalog.
// Usage: swift Scripts/generate-icon.swift [output-directory]
//
// Design (matches LBrowser and Wired Grid): a white squircle, a dot-matrix
// page — folded corner, a heading and lines of text — and a single blue dot.

import AppKit

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "WiredPaper/Resources/Assets.xcassets/AppIcon.appiconset")

let accent = CGColor(srgbRed: 0.184, green: 0.435, blue: 0.859, alpha: 1)

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

func drawIcon(in ctx: CGContext, size: CGFloat) {
    ctx.scaleBy(x: size / 1024, y: size / 1024)

    let tile = CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824), cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.addPath(tile)
    ctx.setFillColor(CGColor(gray: 0.996, alpha: 1))
    ctx.fillPath()
    ctx.addPath(tile)
    ctx.setStrokeColor(CGColor(gray: 0, alpha: 0.10))
    ctx.setLineWidth(4)
    ctx.strokePath()

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
            ctx.setFillColor(CGColor(srgbRed: 0.039, green: 0.039, blue: 0.043, alpha: 0.2 + 0.8 * h))
            ctx.fill(CGRect(x: originX + Double(c) * pitch - s / 2, y: top - Double(r) * pitch - s / 2, width: s, height: s))
        }
    }

    ctx.setFillColor(accent)
    ctx.fillEllipse(in: CGRect(x: 690, y: 700, width: 80, height: 80))
}

func renderPNG(pixels: Int) -> Data {
    let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    drawIcon(in: ctx, size: CGFloat(pixels))
    return NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
}

struct Entry { let size: Int; let scale: Int }
let entries = [16, 32, 128, 256, 512].flatMap { [Entry(size: $0, scale: 1), Entry(size: $0, scale: 2)] }

try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
var images: [[String: String]] = []
for entry in entries {
    let name = "icon_\(entry.size)x\(entry.size)\(entry.scale == 2 ? "@2x" : "").png"
    try renderPNG(pixels: entry.size * entry.scale).write(to: outputDirectory.appendingPathComponent(name))
    images.append(["filename": name, "idiom": "mac", "scale": "\(entry.scale)x", "size": "\(entry.size)x\(entry.size)"])
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys]).write(to: outputDirectory.appendingPathComponent("Contents.json"))
print("Wrote \(entries.count) icon images to \(outputDirectory.path)")
