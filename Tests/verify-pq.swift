import Foundation
import ImageIO
import CoreImage
let url = URL(fileURLWithPath: CommandLine.arguments[1])
let source = CGImageSourceCreateWithURL(url as CFURL, nil)!
for type in [kCGImageAuxiliaryDataTypeHDRGainMap, kCGImageAuxiliaryDataTypeISOGainMap] {
    precondition(CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, type) == nil,
        "Unexpected gain map")
}
let image = CIImage(contentsOf: url, options: [.expandToHDR: true])!
let maximum = image.applyingFilter("CIAreaMaximum", parameters: [kCIInputExtentKey: CIVector(cgRect: image.extent)])
var pixels = [Float](repeating: 0, count: 4)
CIContext().render(maximum, toBitmap: &pixels, rowBytes: 16,
    bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBAf, colorSpace: nil)
precondition(pixels[0] > 1 && pixels[1] > 1 && pixels[2] > 1, "HDR highlights were lost")
print("PASS: no Apple or ISO gain map; decoded HDR maximum RGB = \(pixels.prefix(3))")
