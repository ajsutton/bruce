#!/usr/bin/env swift

import AppKit
import Foundation

enum IconMode {
  case standard
  case full
}

let repositoryRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

func color(_ red: Int, _ green: Int, _ blue: Int) -> NSColor {
  NSColor(
    calibratedRed: CGFloat(red) / 255,
    green: CGFloat(green) / 255,
    blue: CGFloat(blue) / 255,
    alpha: 1
  )
}

func renderIcon(size: Int, mode: IconMode) -> Data {
  guard
    let drawingContext = CGContext(
      data: nil,
      width: size,
      height: size,
      bitsPerComponent: 8,
      bytesPerRow: size * 4,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    )
  else {
    preconditionFailure("Could not create an app icon drawing context.")
  }
  let context = NSGraphicsContext(cgContext: drawingContext, flipped: false)

  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = context
  let bounds = NSRect(x: 0, y: 0, width: size, height: size)
  let isFullBruce = mode == .full
  (isFullBruce ? color(0, 86, 63) : color(237, 227, 209)).setFill()
  bounds.fill()

  let paragraph = NSMutableParagraphStyle()
  paragraph.alignment = .center
  let fontName = isFullBruce ? "HelveticaNeue-CondensedBlack" : "Georgia-Bold"
  let font = NSFont(name: fontName, size: CGFloat(size) * 0.68) ?? .boldSystemFont(ofSize: CGFloat(size) * 0.68)
  let attributes: [NSAttributedString.Key: Any] = [
    .font: font,
    .foregroundColor: isFullBruce ? color(255, 203, 24) : color(23, 62, 59),
    .paragraphStyle: paragraph,
  ]
  let letterBounds = NSRect(
    x: CGFloat(size) * 0.08,
    y: CGFloat(size) * 0.12,
    width: CGFloat(size) * 0.76,
    height: CGFloat(size) * 0.76
  )
  NSAttributedString(string: "B", attributes: attributes).draw(in: letterBounds)

  let punctuationColor = isFullBruce ? color(232, 70, 50) : color(215, 101, 72)
  punctuationColor.setFill()
  if isFullBruce {
    let punctuationAttributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.boldSystemFont(ofSize: CGFloat(size) * 0.27),
      .foregroundColor: punctuationColor,
    ]
    NSAttributedString(string: "!", attributes: punctuationAttributes).draw(
      at: NSPoint(x: CGFloat(size) * 0.72, y: CGFloat(size) * 0.17)
    )
  } else {
    NSBezierPath(
      ovalIn: NSRect(
        x: CGFloat(size) * 0.73,
        y: CGFloat(size) * 0.22,
        width: CGFloat(size) * 0.075,
        height: CGFloat(size) * 0.075
      )
    ).fill()
  }

  NSGraphicsContext.restoreGraphicsState()

  guard
    let image = drawingContext.makeImage(),
    let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
  else {
    preconditionFailure("Could not render app icon.")
  }
  return data
}

func writeIcon(path: String, size: Int, mode: IconMode) throws {
  let destination = repositoryRoot.appendingPathComponent(path)
  try FileManager.default.createDirectory(
    at: destination.deletingLastPathComponent(),
    withIntermediateDirectories: true
  )
  try renderIcon(size: size, mode: mode).write(to: destination)
}

try writeIcon(
  path: "App/Assets-iOS.xcassets/AppIcon.appiconset/Bruce-1024.png",
  size: 1024,
  mode: .standard
)
try writeIcon(
  path: "App/Assets-iOS.xcassets/AppIconFullBruce.appiconset/FullBruce-1024.png",
  size: 1024,
  mode: .full
)

for size in [16, 32, 64, 128, 256, 512, 1024] {
  try writeIcon(
    path: "App/Assets-macOS.xcassets/AppIcon.appiconset/Bruce-\(size).png",
    size: size,
    mode: .standard
  )
}

try writeIcon(
  path: "App/Assets-macOS.xcassets/FullBruceDockIcon.imageset/FullBruce-512.png",
  size: 512,
  mode: .full
)
try writeIcon(
  path: "App/Assets-macOS.xcassets/FullBruceDockIcon.imageset/FullBruce-1024.png",
  size: 1024,
  mode: .full
)
