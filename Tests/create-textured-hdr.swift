import Foundation
import CoreImage
// Deterministic synthetic texture: no photographs or external fixtures needed.
let width = 769, height = 577
var pixels = [Float](repeating: 1, count: width * height * 4)
for y in 0..<height { for x in 0..<width {
    let wave = sin(Float(x) * 0.031) * cos(Float(y) * 0.043)
    let noise = Float((x * 37 + y * 53 + x * y * 7) % 251) / 250
    let v = 0.1 + 3.2 * Float(x) / Float(width) + 0.6 * wave + 0.4 * noise
    let i = (y * width + x) * 4
    pixels[i] = max(0.01, v)
    pixels[i + 1] = max(0.01, v * 0.8 + 0.1 * wave)
    pixels[i + 2] = max(0.01, v * 0.6 + 0.2 * noise)
} }
let data = pixels.withUnsafeBytes { Data($0) }
let image = CIImage(bitmapData: data, bytesPerRow: width * 16,
    size: CGSize(width: width, height: height), format: .RGBAf,
    colorSpace: CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)!)
try CIContext().writeTIFFRepresentation(of: image,
    to: URL(fileURLWithPath: CommandLine.arguments[1]), format: .RGBA16,
    colorSpace: CGColorSpace(name: CGColorSpace.displayP3_PQ)!, options: [:])
