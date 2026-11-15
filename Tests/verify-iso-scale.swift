import Foundation
import CoreImage
import ImageIO

let root = URL(fileURLWithPath: CommandLine.arguments[1])
let context = CIContext()
let space = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)!
for depth in [8, 10] {
    var referencePeak: Float = 0
    var referenceHeadroom: Float = 0
    for scale in [1.0, 1.5, 2.0] {
        let url = root.appendingPathComponent("iso-\(depth)-\(scale)/synthetic-hdr.heic")
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            print("Missing encoded test file:", url.path)
            exit(1)
        }
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)! as NSDictionary
        precondition((props[kCGImagePropertyPixelWidth] as! NSNumber).intValue == 128)
        precondition((props[kCGImagePropertyPixelHeight] as! NSNumber).intValue == 128)
        precondition((props[kCGImagePropertyDepth] as! NSNumber).intValue == depth)
        let auxiliary = CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, kCGImageAuxiliaryDataTypeISOGainMap)! as NSDictionary
        let description = auxiliary[kCGImageAuxiliaryDataInfoDataDescription] as! NSDictionary
        let expected = Int(ceil(128.0 / scale))
        precondition((description["Width"] as! NSNumber).intValue == expected)
        precondition((description["Height"] as! NSNumber).intValue == expected)
        precondition(CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, kCGImageAuxiliaryDataTypeHDRGainMap) == nil)
        let metadata = auxiliary[kCGImageAuxiliaryDataInfoMetadata] as! CGImageMetadata
        let tags = CGImageMetadataCopyTags(metadata)! as NSArray
        let headroomTag = tags.first { value in
            CGImageMetadataTagCopyName(value as! CGImageMetadataTag)! as String == "AlternateHeadroom"
        } as! CGImageMetadataTag
        let headroom = Float(CGImageMetadataTagCopyValue(headroomTag)! as! String)!
        let image = CIImage(contentsOf: url, options: [.expandToHDR: true])!
        // Sample a flat highlight patch away from the resampled boundary.
        let patch = image.cropped(to: CGRect(x: 96, y: 48, width: 8, height: 8))
            .applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(x: 96, y: 48, z: 8, w: 8)])
        var pixels = [Float](repeating: 0, count: 4)
        context.render(patch, toBitmap: &pixels, rowBytes: 16,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBAf, colorSpace: space)
        let peak = pixels.prefix(3).max()!
        precondition(peak > 1.5, "HDR reconstruction lost highlights")
        if scale == 1 { referencePeak = peak; referenceHeadroom = headroom }
        precondition(abs(headroom - referenceHeadroom) < 0.001)
        precondition(abs(peak - referencePeak) / referencePeak < 0.08)
        print("PASS ISO \(depth) bit, scale \(scale), map \(expected)x\(expected), headroom \(headroom), highlight \(peak)")
    }
}
