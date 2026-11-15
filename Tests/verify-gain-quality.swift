import Foundation
import CoreImage
import ImageIO
let context=CIContext()
let space=CGColorSpace(name:CGColorSpace.extendedLinearDisplayP3)!
func load(_ path:String)->([Float],Float,[String:String],Int,Int,Int) {
 let url=URL(fileURLWithPath:path)
 let src=CGImageSourceCreateWithURL(url as CFURL,nil)!
 let props=CGImageSourceCopyPropertiesAtIndex(src,0,nil)! as NSDictionary
 let aux=CGImageSourceCopyAuxiliaryDataInfoAtIndex(src,0,kCGImageAuxiliaryDataTypeISOGainMap)! as NSDictionary
 let desc=aux[kCGImageAuxiliaryDataInfoDataDescription]! as! NSDictionary
 let metadata=aux[kCGImageAuxiliaryDataInfoMetadata]! as! CGImageMetadata
 let data=CGImageMetadataCreateXMPData(metadata,nil)! as Data
 // Pointer addresses in description aren't stable; the serialized XMP is.
 let image=CIImage(contentsOf:url,options:[.expandToHDR:true])!
 let scale=min(1,512/max(image.extent.width,image.extent.height))
 let down=image.applyingFilter("CILanczosScaleTransform",parameters:[kCIInputScaleKey:scale,kCIInputAspectRatioKey:1])
 let w=Int(down.extent.width),h=Int(down.extent.height)
 var pixels=[Float](repeating:0,count:w*h*4)
 context.render(down,toBitmap:&pixels,rowBytes:w*16,bounds:CGRect(x:0,y:0,width:w,height:h),format:.RGBAf,colorSpace:space)
 let peak=pixels.enumerated().filter{$0.offset%4 != 3}.map{$0.element}.max()!
 return (pixels,peak,["xmp":data.base64EncodedString()],desc["Width"] as! Int,desc["Height"] as! Int,props[kCGImagePropertyDepth] as! Int)
}
let baseline=load(CommandLine.arguments[1])
precondition(baseline.1>1.1,"baseline lost HDR")
for path in CommandLine.arguments.dropFirst(2) {
 let test=load(path)
 precondition(test.0.count==baseline.0.count && test.2==baseline.2 && test.3==baseline.3 && test.4==baseline.4 && test.5==baseline.5,"metadata or dimensions changed")
 var sum=0.0, energy=0.0, maxError=0.0
 for i in test.0.indices where i%4 != 3 {
  let error=abs(Double(test.0[i])-Double(baseline.0[i]))
  sum+=error;energy+=abs(Double(baseline.0[i]));maxError=max(maxError,error)
 }
 let relative=sum/energy
 precondition(relative<0.06 && test.1>1.1,"HDR reconstruction drifted excessively")
 print(URL(fileURLWithPath:path).lastPathComponent,"relative mean error",relative,"peak",test.1,"max error",maxError,"map",test.3,test.4,"main bits",test.5)
}
