#!/usr/bin/env swift

import AppKit
import CoreGraphics
import Foundation

enum AppIconStyle {
    static let canvasSize = 1024
    static let outputPath = "SimulateLocation/Assets.xcassets/AppIcon.appiconset/AppIcon.png"

    static let tealTop = CGColor(red: 0.0588, green: 0.4627, blue: 0.4314, alpha: 1.0)
    static let tealBottom = CGColor(red: 0.0667, green: 0.3686, blue: 0.3490, alpha: 1.0)
    static let routeColor = CGColor(red: 0.8000, green: 0.9843, blue: 0.9451, alpha: 0.88)
    static let pinColor = CGColor(red: 0.9725, green: 0.9804, blue: 0.9882, alpha: 1.0)
    static let innerTeal = CGColor(red: 0.0588, green: 0.4627, blue: 0.4314, alpha: 1.0)
}

func drawRoute(in context: CGContext) {
    context.saveGState()
    context.setStrokeColor(AppIconStyle.routeColor)
    context.setLineWidth(54)
    context.setLineCap(.round)

    let path = CGMutablePath()
    path.move(to: CGPoint(x: 146, y: 696))
    path.addCurve(
        to: CGPoint(x: 508, y: 616),
        control1: CGPoint(x: 286, y: 568),
        control2: CGPoint(x: 374, y: 742)
    )
    path.addCurve(
        to: CGPoint(x: 874, y: 436),
        control1: CGPoint(x: 646, y: 486),
        control2: CGPoint(x: 718, y: 574)
    )

    context.addPath(path)
    context.strokePath()
    context.restoreGState()
}

func drawPin(in context: CGContext) {
    context.saveGState()

    context.setShadow(
        offset: CGSize(width: 0, height: 18),
        blur: 20,
        color: CGColor(red: 0.0157, green: 0.1843, blue: 0.1804, alpha: 0.32)
    )

    let pinPath = CGMutablePath()
    pinPath.move(to: CGPoint(x: 512, y: 822))
    pinPath.addCurve(
        to: CGPoint(x: 278, y: 410),
        control1: CGPoint(x: 512, y: 822),
        control2: CGPoint(x: 278, y: 584)
    )
    pinPath.addCurve(
        to: CGPoint(x: 512, y: 176),
        control1: CGPoint(x: 278, y: 280),
        control2: CGPoint(x: 382, y: 176)
    )
    pinPath.addCurve(
        to: CGPoint(x: 746, y: 410),
        control1: CGPoint(x: 642, y: 176),
        control2: CGPoint(x: 746, y: 280)
    )
    pinPath.addCurve(
        to: CGPoint(x: 512, y: 822),
        control1: CGPoint(x: 746, y: 584),
        control2: CGPoint(x: 512, y: 822)
    )
    pinPath.closeSubpath()

    context.setFillColor(AppIconStyle.pinColor)
    context.addPath(pinPath)
    context.fillPath()

    context.setShadow(offset: .zero, blur: 0, color: nil)
    context.setFillColor(AppIconStyle.innerTeal)
    context.fillEllipse(in: CGRect(x: 424, y: 322, width: 176, height: 176))
    context.setFillColor(AppIconStyle.pinColor)
    context.fillEllipse(in: CGRect(x: 478, y: 376, width: 68, height: 68))

    context.restoreGState()
}

let size = AppIconStyle.canvasSize
let colorSpace = CGColorSpaceCreateDeviceRGB()

guard let context = CGContext(
    data: nil,
    width: size,
    height: size,
    bitsPerComponent: 8,
    bytesPerRow: size * 4,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
) else {
    fatalError("Unable to create graphics context.")
}

context.interpolationQuality = .high
context.setAllowsAntialiasing(true)
context.setShouldAntialias(true)
context.translateBy(x: 0, y: CGFloat(size))
context.scaleBy(x: 1, y: -1)

let backgroundGradient = CGGradient(
    colorsSpace: colorSpace,
    colors: [AppIconStyle.tealTop, AppIconStyle.tealBottom] as CFArray,
    locations: [0, 1]
)!
context.drawLinearGradient(
    backgroundGradient,
    start: CGPoint(x: 0, y: 0),
    end: CGPoint(x: size, y: size),
    options: []
)

drawRoute(in: context)
drawPin(in: context)

guard let image = context.makeImage() else {
    fatalError("Unable to create app icon image.")
}

let bitmap = NSBitmapImageRep(cgImage: image)
guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Unable to encode app icon PNG.")
}

let outputURL = URL(fileURLWithPath: AppIconStyle.outputPath)
try FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)
try pngData.write(to: outputURL, options: .atomic)
print("Wrote \(AppIconStyle.outputPath)")
