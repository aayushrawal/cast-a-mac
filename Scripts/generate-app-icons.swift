#!/usr/bin/env swift

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

private let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
private let assetCatalog = root
    .appendingPathComponent("Apps/CastClient/Assets.xcassets")
private let appIconSet = assetCatalog.appendingPathComponent("AppIcon.appiconset")
private let macIconSet = root.appendingPathComponent("Assets/CastAMac.iconset")

private struct IconOutput {
    let url: URL
    let pixels: Int
    let macStyle: Bool
}

private let iPadOutputs: [(String, Int)] = [
    ("AppIcon-20.png", 20),
    ("AppIcon-20@2x.png", 40),
    ("AppIcon-29.png", 29),
    ("AppIcon-29@2x.png", 58),
    ("AppIcon-40.png", 40),
    ("AppIcon-40@2x.png", 80),
    ("AppIcon-76.png", 76),
    ("AppIcon-76@2x.png", 152),
    ("AppIcon-83.5@2x.png", 167),
    ("AppIcon-1024.png", 1_024)
]

private let macOutputs: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1_024)
]

try FileManager.default.createDirectory(
    at: appIconSet,
    withIntermediateDirectories: true
)
try FileManager.default.createDirectory(
    at: macIconSet,
    withIntermediateDirectories: true
)

private let outputs = iPadOutputs.map {
    IconOutput(
        url: appIconSet.appendingPathComponent($0.0),
        pixels: $0.1,
        macStyle: false
    )
} + macOutputs.map {
    IconOutput(
        url: macIconSet.appendingPathComponent($0.0),
        pixels: $0.1,
        macStyle: true
    )
}

for output in outputs {
    let alphaInfo: CGImageAlphaInfo = output.macStyle
        ? .premultipliedLast
        : .noneSkipLast
    guard let context = CGContext(
        data: nil,
        width: output.pixels,
        height: output.pixels,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: alphaInfo.rawValue
    ) else {
        throw CocoaError(.fileWriteUnknown)
    }

    drawIcon(in: context, size: CGFloat(output.pixels), macStyle: output.macStyle)

    guard let image = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(
              output.url as CFURL,
              UTType.png.identifier as CFString,
              1,
              nil
          ) else {
        throw CocoaError(.fileWriteUnknown)
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw CocoaError(.fileWriteUnknown)
    }
}

private func drawIcon(in context: CGContext, size: CGFloat, macStyle: Bool) {
    context.setAllowsAntialiasing(true)
    context.interpolationQuality = .high

    let inset = macStyle ? size * 0.065 : 0
    let tileRect = CGRect(
        x: inset,
        y: inset,
        width: size - inset * 2,
        height: size - inset * 2
    )
    let cornerRadius = macStyle ? size * 0.205 : 0
    let tilePath = CGPath(
        roundedRect: tileRect,
        cornerWidth: cornerRadius,
        cornerHeight: cornerRadius,
        transform: nil
    )

    if macStyle {
        context.setShadow(
            offset: CGSize(width: 0, height: -size * 0.018),
            blur: size * 0.055,
            color: CGColor(gray: 0, alpha: 0.34)
        )
        context.addPath(tilePath)
        context.setFillColor(CGColor(gray: 0.05, alpha: 1))
        context.fillPath()
        context.setShadow(offset: .zero, blur: 0)
    }

    context.saveGState()
    context.addPath(tilePath)
    context.clip()

    let colors = [
        CGColor(red: 0.025, green: 0.075, blue: 0.15, alpha: 1),
        CGColor(red: 0.02, green: 0.28, blue: 0.48, alpha: 1)
    ] as CFArray
    let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: colors,
        locations: [0, 1]
    )!
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: size * 0.18, y: size * 0.1),
        end: CGPoint(x: size * 0.84, y: size * 0.92),
        options: []
    )

    context.setFillColor(
        CGColor(red: 0.08, green: 0.72, blue: 0.95, alpha: 0.13)
    )
    context.fillEllipse(
        in: CGRect(
            x: size * 0.36,
            y: size * 0.40,
            width: size * 0.72,
            height: size * 0.72
        )
    )
    context.restoreGState()

    let stroke = max(1.5, size * 0.052)
    let screenRect = CGRect(
        x: size * 0.20,
        y: size * 0.29,
        width: size * 0.60,
        height: size * 0.40
    )
    let screenPath = CGPath(
        roundedRect: screenRect,
        cornerWidth: size * 0.055,
        cornerHeight: size * 0.055,
        transform: nil
    )
    context.addPath(screenPath)
    context.setStrokeColor(
        CGColor(red: 0.91, green: 0.98, blue: 1, alpha: 1)
    )
    context.setLineWidth(stroke)
    context.setLineJoin(.round)
    context.strokePath()

    context.setLineCap(.round)
    context.move(to: CGPoint(x: size * 0.42, y: size * 0.21))
    context.addLine(to: CGPoint(x: size * 0.58, y: size * 0.21))
    context.move(to: CGPoint(x: size * 0.50, y: size * 0.21))
    context.addLine(to: CGPoint(x: size * 0.50, y: size * 0.30))
    context.setLineWidth(stroke)
    context.strokePath()

    let castColor = CGColor(
        red: 0.24,
        green: 0.88,
        blue: 1,
        alpha: 1
    )
    context.setStrokeColor(castColor)
    context.setFillColor(castColor)
    context.setLineWidth(max(1.2, size * 0.038))
    context.setLineCap(.round)

    let castOrigin = CGPoint(x: size * 0.31, y: size * 0.39)
    context.fillEllipse(
        in: CGRect(
            x: castOrigin.x - size * 0.026,
            y: castOrigin.y - size * 0.026,
            width: size * 0.052,
            height: size * 0.052
        )
    )
    for radius in [size * 0.105, size * 0.19] {
        context.addArc(
            center: castOrigin,
            radius: radius,
            startAngle: 0,
            endAngle: .pi / 2,
            clockwise: false
        )
        context.strokePath()
    }
}

print("Generated iPad and macOS application icons.")
