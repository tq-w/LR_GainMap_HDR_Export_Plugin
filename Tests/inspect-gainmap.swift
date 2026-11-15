import Foundation
import ImageIO
for path in CommandLine.arguments.dropFirst() {
    let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil)!
    let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)! as NSDictionary
    let auxiliary = CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, kCGImageAuxiliaryDataTypeHDRGainMap)! as NSDictionary
    let description = auxiliary[kCGImageAuxiliaryDataInfoDataDescription] as! NSDictionary
    let result: [String: Any] = [
        "path": path,
        "mainWidth": properties[kCGImagePropertyPixelWidth]!,
        "mainHeight": properties[kCGImagePropertyPixelHeight]!,
        "gainMapDescription": description,
    ]
    let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
    print(String(data: data, encoding: .utf8)!)
}
