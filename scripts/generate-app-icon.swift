#!/usr/bin/env swift

import AppKit
import Foundation

let scriptPath = CommandLine.arguments.first ?? "scripts/generate-app-icon.swift"
let scriptURL = URL(fileURLWithPath: scriptPath, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
    .standardizedFileURL
let rootURL = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
let assetsURL = rootURL.appendingPathComponent("macos/GWSMenuBar/Assets", isDirectory: true)
let iconsetURL = FileManager.default.temporaryDirectory.appendingPathComponent("GWSMenu-AppIcon-\(UUID().uuidString).iconset", isDirectory: true)
let outputURL = assetsURL.appendingPathComponent("AppIcon.icns")

try FileManager.default.createDirectory(at: assetsURL, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)
defer {
    try? FileManager.default.removeItem(at: iconsetURL)
}

struct IconSize {
    let filename: String
    let pixels: Int
}

let sizes = [
    IconSize(filename: "icon_16x16.png", pixels: 16),
    IconSize(filename: "icon_16x16@2x.png", pixels: 32),
    IconSize(filename: "icon_32x32.png", pixels: 32),
    IconSize(filename: "icon_32x32@2x.png", pixels: 64),
    IconSize(filename: "icon_128x128.png", pixels: 128),
    IconSize(filename: "icon_128x128@2x.png", pixels: 256),
    IconSize(filename: "icon_256x256.png", pixels: 256),
    IconSize(filename: "icon_256x256@2x.png", pixels: 512),
    IconSize(filename: "icon_512x512.png", pixels: 512),
    IconSize(filename: "icon_512x512@2x.png", pixels: 1024)
]

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: red / 255, green: green / 255, blue: blue / 255, alpha: alpha)
}

func scaled(_ value: CGFloat, _ scale: CGFloat) -> CGFloat {
    value * scale
}

func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, _ scale: CGFloat) -> NSRect {
    NSRect(x: scaled(x, scale), y: scaled(y, scale), width: scaled(width, scale), height: scaled(height, scale))
}

func roundedPath(_ rect: NSRect, _ radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

func fillRounded(_ rect: NSRect, radius: CGFloat, color: NSColor) {
    color.setFill()
    roundedPath(rect, radius).fill()
}

func drawIcon(pixels: Int, to url: URL) throws {
    let size = NSSize(width: pixels, height: pixels)
    let scale = CGFloat(pixels) / 1024
    let image = NSImage(size: size)

    image.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high
    NSColor.clear.setFill()
    NSRect(origin: .zero, size: size).fill()

    let baseRect = rect(92, 92, 840, 840, scale)
    let baseRadius = scaled(210, scale)
    let basePath = roundedPath(baseRect, baseRadius)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowBlurRadius = scaled(36, scale)
    shadow.shadowOffset = NSSize(width: 0, height: scaled(-24, scale))
    shadow.shadowColor = color(31, 41, 55, 0.20)
    shadow.set()
    color(255, 255, 255).setFill()
    basePath.fill()
    NSGraphicsContext.restoreGraphicsState()

    basePath.addClip()
    let gradient = NSGradient(colors: [
        color(255, 255, 255),
        color(246, 248, 252)
    ])
    gradient?.draw(in: baseRect, angle: 90)

    fillRounded(rect(190, 742, 644, 86, scale), radius: scaled(43, scale), color: color(32, 33, 36))
    fillRounded(rect(242, 769, 36, 32, scale), radius: scaled(16, scale), color: color(66, 133, 244))
    fillRounded(rect(298, 769, 36, 32, scale), radius: scaled(16, scale), color: color(234, 67, 53))
    fillRounded(rect(354, 769, 36, 32, scale), radius: scaled(16, scale), color: color(251, 188, 4))
    fillRounded(rect(410, 769, 36, 32, scale), radius: scaled(16, scale), color: color(52, 168, 83))
    fillRounded(rect(590, 770, 192, 28, scale), radius: scaled(14, scale), color: color(255, 255, 255, 0.82))

    let tileRadius = scaled(64, scale)
    fillRounded(rect(230, 510, 248, 248, scale), radius: tileRadius, color: color(66, 133, 244))
    fillRounded(rect(546, 510, 248, 248, scale), radius: tileRadius, color: color(234, 67, 53))
    fillRounded(rect(230, 194, 248, 248, scale), radius: tileRadius, color: color(251, 188, 4))
    fillRounded(rect(546, 194, 248, 248, scale), radius: tileRadius, color: color(52, 168, 83))

    NSGraphicsContext.saveGraphicsState()
    let cardShadow = NSShadow()
    cardShadow.shadowBlurRadius = scaled(28, scale)
    cardShadow.shadowOffset = NSSize(width: 0, height: scaled(-14, scale))
    cardShadow.shadowColor = color(15, 23, 42, 0.20)
    cardShadow.set()
    fillRounded(rect(320, 330, 384, 342, scale), radius: scaled(82, scale), color: color(255, 255, 255))
    NSGraphicsContext.restoreGraphicsState()

    fillRounded(rect(382, 570, 104, 42, scale), radius: scaled(21, scale), color: color(66, 133, 244))
    fillRounded(rect(382, 494, 260, 38, scale), radius: scaled(19, scale), color: color(32, 33, 36))
    fillRounded(rect(382, 432, 210, 34, scale), radius: scaled(17, scale), color: color(95, 99, 104))
    fillRounded(rect(382, 376, 160, 30, scale), radius: scaled(15, scale), color: color(154, 160, 166))

    let ringRect = rect(586, 556, 56, 56, scale)
    color(52, 168, 83).setStroke()
    let ring = NSBezierPath(ovalIn: ringRect)
    ring.lineWidth = max(1, scaled(12, scale))
    ring.stroke()

    image.unlockFocus()

    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "GWSMenuIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to render icon PNG"])
    }
    try png.write(to: url)
}

for size in sizes {
    try drawIcon(pixels: size.pixels, to: iconsetURL.appendingPathComponent(size.filename))
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetURL.path, "-o", outputURL.path]
try process.run()
process.waitUntilExit()

if process.terminationStatus != 0 {
    throw NSError(domain: "GWSMenuIcon", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "iconutil failed"])
}

print(outputURL.path)
