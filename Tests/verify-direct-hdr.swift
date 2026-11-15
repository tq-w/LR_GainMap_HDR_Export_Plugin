import Foundation
import CoreGraphics
import ImageIO
let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL, nil)!
let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)! as NSDictionary
precondition((properties[kCGImagePropertyDepth] as! NSNumber).intValue == 10)
let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
precondition(CommandLine.arguments[2] == "pq" ? CGColorSpaceIsPQBased(image.colorSpace!) : CGColorSpaceIsHLGBased(image.colorSpace!))
precondition(CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, kCGImageAuxiliaryDataTypeHDRGainMap) == nil)
precondition(CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, kCGImageAuxiliaryDataTypeISOGainMap) == nil)
print("PASS direct HDR transfer and 10-bit encoding:", CommandLine.arguments[2])
