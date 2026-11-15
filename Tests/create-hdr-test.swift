import CoreImage
import Foundation
let context = CIContext()
let bounds = CGRect(x: 0, y: 0, width: 128, height: 128)
var pixels = [Float]()
for _ in 0..<128 {
    for x in 0..<128 {
        pixels += x < 64 ? [0.15, 0.25, 0.4, 1] : [4, 4, 4, 1]
    }
}
let data = pixels.withUnsafeBytes { Data($0) }
let image = CIImage(bitmapData: data, bytesPerRow: 128 * 16,
    size: bounds.size, format: .RGBAf,
    colorSpace: CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)!)
try context.writeTIFFRepresentation(of: image,
    to: URL(fileURLWithPath: CommandLine.arguments[1]), format: .RGBA16,
    colorSpace: CGColorSpace(name: CGColorSpace.displayP3_PQ)!, options: [:])
print("Created synthetic PQ HDR TIFF")
