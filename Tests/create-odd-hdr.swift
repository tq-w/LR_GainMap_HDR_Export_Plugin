import Foundation
import CoreImage
let width = 129, height = 97
var pixels = [Float]()
for _ in 0..<height {
    for x in 0..<width {
        let value = 0.05 + 3.95 * Float(x) / Float(width - 1)
        pixels += [value, value * 0.9, value * 0.8, 1]
    }
}
let data = pixels.withUnsafeBytes { Data($0) }
let image = CIImage(bitmapData: data, bytesPerRow: width * 16,
    size: CGSize(width: width, height: height), format: .RGBAf,
    colorSpace: CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)!)
try CIContext().writeTIFFRepresentation(of: image,
    to: URL(fileURLWithPath: CommandLine.arguments[1]), format: .RGBA16,
    colorSpace: CGColorSpace(name: CGColorSpace.displayP3_PQ)!, options: [:])
