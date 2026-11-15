import Foundation
import ImageIO
for path in CommandLine.arguments.dropFirst() {
    let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil)!
    let index = CGImageSourceGetPrimaryImageIndex(source)
    let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil)! as NSDictionary
    print(URL(fileURLWithPath: path).lastPathComponent, "primary-index", index,
        "width", properties[kCGImagePropertyPixelWidth] ?? "?",
        "height", properties[kCGImagePropertyPixelHeight] ?? "?",
        "depth", properties[kCGImagePropertyDepth] ?? "?",
        "profile", properties[kCGImagePropertyProfileName] ?? "?")
    for (name, type) in [("Apple", kCGImageAuxiliaryDataTypeHDRGainMap), ("ISO", kCGImageAuxiliaryDataTypeISOGainMap)] {
        if let auxiliary = CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, index, type) as NSDictionary? {
            print(name, "gain map present:", auxiliary[kCGImageAuxiliaryDataInfoDataDescription] ?? "no description")
            if let metadata = auxiliary[kCGImageAuxiliaryDataInfoMetadata] {
                let tags = CGImageMetadataCopyTags(metadata as! CGImageMetadata) as NSArray? ?? []
                for tag in tags {
                    let t = tag as! CGImageMetadataTag
                    print(" ", CGImageMetadataTagCopyName(t) ?? "?" as CFString,
                        CGImageMetadataTagCopyValue(t) ?? "?" as CFString)
                }
            }
        } else { print(name, "gain map absent") }
    }
}
