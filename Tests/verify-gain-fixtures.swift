import Foundation
import ImageIO
let root=URL(fileURLWithPath:CommandLine.arguments[1])
for depth in [8,10] { for scale in [1.0,1.5,2.0] { for quality in [0,1] {
 let scaleText=scale==1 ? "1" : scale==2 ? "2" : "1.5"
 let url=root.appendingPathComponent("odd-\(depth)-\(scaleText)-\(quality)/odd-hdr.heic")
 let src=CGImageSourceCreateWithURL(url as CFURL,nil)!
 let props=CGImageSourceCopyPropertiesAtIndex(src,0,nil)! as NSDictionary
 precondition(props[kCGImagePropertyPixelWidth] as! Int==129 && props[kCGImagePropertyPixelHeight] as! Int==97)
 precondition(props[kCGImagePropertyDepth] as! Int==depth)
 let aux=CGImageSourceCopyAuxiliaryDataInfoAtIndex(src,0,kCGImageAuxiliaryDataTypeISOGainMap)! as NSDictionary
 let desc=aux[kCGImageAuxiliaryDataInfoDataDescription]! as! NSDictionary
 precondition(desc["Width"] as! Int==Int(ceil(129/scale)))
 precondition(desc["Height"] as! Int==Int(ceil(97/scale)))
} } }
print("PASS: main 129x97 at 8/10 bit; ISO map dimensions correct for every custom quality and scale")
