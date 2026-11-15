import Foundation
import CoreImage
import CoreVideo
import ImageIO

// Keep the ISO metadata as ImageIO auxiliary data. Passing it back through
// CIImageRepresentationOption.hdrGainMapImage can produce an Apple-format map.
func writeScaledISOGainMap(context: CIContext, base: CIImage,
        generationOptions: [CIImageRepresentationOption: Any], colorSpace: CGColorSpace,
        scale: Float, tenBit: Bool, jpeg: Bool, gainQuality: Double? = nil, output: URL) throws {
    func failure(_ message: String) -> NSError {
        NSError(domain: "ISOExport", code: 1,
                userInfo: [NSLocalizedDescriptionKey: message])
    }
    var options = generationOptions
    options[CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String)] = 1.0
    guard let temporary = context.heifRepresentation(of: base, format: .RGBA8,
            colorSpace: colorSpace, options: options),
          let source = CGImageSourceCreateWithData(temporary as CFData, nil),
          var auxiliary = CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0,
            kCGImageAuxiliaryDataTypeISOGainMap) as? [String: Any],
          var description = auxiliary[kCGImageAuxiliaryDataInfoDataDescription as String] as? [String: Any],
          let pixelFormat = description["PixelFormat"] as? NSNumber,
          pixelFormat.uint32Value == kCVPixelFormatType_OneComponent8,
          let map = CIImage(data: temporary, options: [.auxiliaryHDRGainMap: true]) else {
        throw failure("无法生成用于缩放的单通道 ISO 增益图。")
    }

    let width = max(1, Int(ceil(map.extent.width / CGFloat(scale))))
    let height = max(1, Int(ceil(map.extent.height / CGFloat(scale))))
    let bounds = CGRect(x: 0, y: 0, width: width, height: height)
    let scaleY = CGFloat(height) / map.extent.height
    let aspect = (CGFloat(width) / map.extent.width) / scaleY
    let resized = map.transformed(by: CGAffineTransform(
        translationX: -map.extent.minX, y: -map.extent.minY))
        .applyingFilter("CILanczosScaleTransform", parameters: [
            kCIInputScaleKey: scaleY, kCIInputAspectRatioKey: aspect])
        .cropped(to: bounds)
    let rowBytes = (width + 63) & ~63
    var pixels = [UInt8](repeating: 0, count: rowBytes * height)
    context.render(resized, toBitmap: &pixels, rowBytes: rowBytes,
        bounds: bounds, format: .L8, colorSpace: nil)
    description["Width"] = width
    description["Height"] = height
    description["BytesPerRow"] = rowBytes
    description["PixelFormat"] = kCVPixelFormatType_OneComponent8
    auxiliary[kCGImageAuxiliaryDataInfoData as String] = Data(pixels)
    auxiliary[kCGImageAuxiliaryDataInfoDataDescription as String] = description

    // Encode the original SDR base once at the requested depth and quality.
    guard let primary = context.createCGImage(base, from: base.extent,
            format: tenBit && !jpeg ? .RGB10 : .RGBA8, colorSpace: colorSpace) else {
        throw failure("无法渲染 HEIC 主图。")
    }
    let encoded = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(encoded,
            (jpeg ? "public.jpeg" : "public.heic") as CFString, 1, nil) else {
        throw failure("无法创建 ISO HDR 输出文件。")
    }
    var properties = base.properties
    properties[kCGImageDestinationLossyCompressionQuality as String] =
        generationOptions[CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String)] ?? 0.85
    CGImageDestinationAddImage(destination, primary, properties as CFDictionary)
    CGImageDestinationAddAuxiliaryDataInfo(destination, kCGImageAuxiliaryDataTypeISOGainMap,
        auxiliary as CFDictionary)
    guard CGImageDestinationFinalize(destination),
          let check = CGImageSourceCreateWithData(encoded, nil),
          let saved = CGImageSourceCopyAuxiliaryDataInfoAtIndex(check, 0,
            kCGImageAuxiliaryDataTypeISOGainMap) as? [String: Any],
          let savedDescription = saved[kCGImageAuxiliaryDataInfoDataDescription as String] as? [String: Any],
          (savedDescription["Width"] as? NSNumber)?.intValue == width,
          (savedDescription["Height"] as? NSNumber)?.intValue == height else {
        throw failure("ISO 增益图写入或尺寸校验失败。")
    }
    let result = try gainQuality.map { try compressISOGainMap(encoded as Data, auxiliary: auxiliary, quality: $0) } ?? (encoded as Data)
    try result.write(to: output, options: .atomic)
}
