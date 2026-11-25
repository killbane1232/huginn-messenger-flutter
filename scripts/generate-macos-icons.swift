#!/usr/bin/env swift
import AppKit

// Run from the project root. Normalize visible artwork, not just the PNG canvas:
// generated images may have unequal transparent margins or unequal side lengths.
let source = URL(fileURLWithPath: "macos/AppIcon-source.png")
let output = URL(fileURLWithPath: "macos/Runner/Assets.xcassets/AppIcon.appiconset")
let bitmap = NSBitmapImageRep(data: try Data(contentsOf: source))!
var minX = bitmap.pixelsWide, minY = bitmap.pixelsHigh, maxX = -1, maxY = -1
for y in 0..<bitmap.pixelsHigh {
  for x in 0..<bitmap.pixelsWide where bitmap.colorAt(x: x, y: y)!.alphaComponent > 0.5 {
    minX = min(minX, x); maxX = max(maxX, x)
    minY = min(minY, y); maxY = max(maxY, y)
  }
}
precondition(maxX >= minX && maxY >= minY, "Source icon is empty")
let bounds = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
let artwork = bitmap.cgImage!.cropping(to: bounds)!
let background = bitmap.colorAt(x: (minX + maxX) / 2, y: minY + 8)!
  .usingColorSpace(.sRGB)!
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
let context = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8,
  bytesPerRow: 0, space: colorSpace,
  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
let frame = CGRect(x: 100, y: 100, width: 824, height: 824)
context.addPath(CGPath(roundedRect: frame, cornerWidth: 185, cornerHeight: 185,
                      transform: nil))
context.clip()
// Opaque fill removes any irregular alpha left around the generated contour.
context.setFillColor(background.cgColor)
context.fill(frame)
context.interpolationQuality = .high
context.draw(artwork, in: frame)
let master = context.makeImage()!

for size in [16, 32, 64, 128, 256, 512, 1024] {
  let scaled = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
    bytesPerRow: 0, space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
  scaled.interpolationQuality = .high
  scaled.draw(master, in: CGRect(x: 0, y: 0, width: size, height: size))
  let result = NSBitmapImageRep(cgImage: scaled.makeImage()!)
  let png = result.representation(using: .png, properties: [:])!
  try png.write(to: output.appendingPathComponent("app_icon_\(size).png"))
  print("Generated \(size)x\(size)")
}
