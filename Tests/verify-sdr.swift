import Foundation
import CoreGraphics
import CoreImage
import ImageIO
let inputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
let source = CGImageSourceCreateWithURL(inputURL as CFURL, nil)!
let output = CGImageSourceCreateWithURL(outputURL as CFURL, nil)!
let expectedDepth = Int(CommandLine.arguments[3])!
let originalProperties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)! as NSDictionary
let outputProperties = CGImageSourceCopyPropertiesAtIndex(output, 0, nil)! as NSDictionary
for key in [kCGImagePropertyPixelWidth, kCGImagePropertyPixelHeight] {
    precondition((originalProperties[key] as! NSNumber) == (outputProperties[key] as! NSNumber))
}
precondition((outputProperties[kCGImagePropertyDepth] as! NSNumber).intValue == expectedDepth)
let originalImage = CGImageSourceCreateImageAtIndex(source, 0, nil)!
let outputImage = CGImageSourceCreateImageAtIndex(output, 0, nil)!
let outputSpace = outputImage.colorSpace!
precondition(!CGColorSpaceUsesITUR_2100TF(outputSpace))
precondition((originalImage.colorSpace!.name as String?) == (outputSpace.name as String?), "SDR profile changed")
for type in [kCGImageAuxiliaryDataTypeHDRGainMap, kCGImageAuxiliaryDataTypeISOGainMap] {
    precondition(CGImageSourceCopyAuxiliaryDataInfoAtIndex(output, 0, type) == nil)
}
let context = CIContext()
let space = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)!
func average(_ image: CGImage) -> [Float] {
    let original = CIImage(cgImage: image)
    let filtered = original.applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(cgRect: original.extent)])
    var pixel = [Float](repeating: 0, count: 4)
    context.render(filtered, toBitmap: &pixel, rowBytes: 16,
        bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBAf, colorSpace: space)
    return pixel
}
let reference = average(originalImage), actual = average(outputImage)
for i in 0..<3 { precondition(abs(reference[i] - actual[i]) < 0.015, "SDR appearance changed") }
print("PASS SDR", expectedDepth, "bit, preserved profile and appearance, no gain map")
