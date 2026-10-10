// Deterministic exports of the existing Linefold artwork for the iOS catalog.
// Run: swift app/tool/generate_ios_app_icons.swift (from the repository root).
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let app = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let source = CGImageSourceCreateWithURL(app.appendingPathComponent("design/linefold-icon-v1.png") as CFURL, nil)!
let artwork = CGImageSourceCreateImageAtIndex(source, 0, nil)!
let catalog = app.appendingPathComponent("ios/Runner/Assets.xcassets/AppIcon.appiconset")
let data = try Data(contentsOf: catalog.appendingPathComponent("Contents.json"))
let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
for image in json["images"] as! [[String: String]] {
  let points = Double(image["size"]!.split(separator: "x")[0])!
  let scale = Double(image["scale"]!.dropLast())!
  let size = Int(points * scale)
  let context = CGContext(
    data: nil, width: size, height: size, bitsPerComponent: 8,
    bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
  )!
  let bounds = CGRect(x: 0, y: 0, width: size, height: size)
  context.setFillColor(CGColor(gray: 0.12, alpha: 1))
  context.fill(bounds)
  context.interpolationQuality = .high
  context.draw(artwork, in: bounds)
  let destination = CGImageDestinationCreateWithURL(
    catalog.appendingPathComponent(image["filename"]!) as CFURL,
    UTType.png.identifier as CFString, 1, nil
  )!
  CGImageDestinationAddImage(destination, context.makeImage()!, nil)
  precondition(CGImageDestinationFinalize(destination))
}
print("Generated opaque Linefold iOS icons from the shared artwork")
