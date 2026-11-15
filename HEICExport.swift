import Foundation
import CoreGraphics
import ImageIO
import Darwin

// Lightroom-facing runner: validate the rendered TIFF, encode in a private
// staging directory, then publish with an atomic collision policy.
func failure(_ message: String) -> NSError {
    NSError(domain: "HEICExport", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
}

struct ExportRequest {
    let input: URL
    let folder: URL
    var mode = "iso"
    var depth = 10
    var scale = 1.0
    var quality = 0.85
    var gainQuality: Double? = nil
    var collision = "rename"

    init(_ args: [String]) throws {
        guard args.count >= 3 else { throw failure("用法：HEICExport 输入文件 输出文件夹 --mode iso|apple|pq|hlg|sips --collision rename|skip|overwrite") }
        input = URL(fileURLWithPath: args[1]).standardizedFileURL
        folder = URL(fileURLWithPath: args[2]).standardizedFileURL
        var i = 3
        while i < args.count {
            guard i + 1 < args.count else { throw failure("参数缺少取值：\(args[i])") }
            let value = args[i + 1]
            switch args[i] {
            case "--mode": mode = value
            case "--depth": depth = Int(value) ?? 0
            case "--scale": scale = Double(value) ?? .nan
            case "--quality": quality = Double(value) ?? .nan
            case "--gain-quality": gainQuality = Double(value) ?? .nan
            case "--collision": collision = value
            default: throw failure("未知参数：\(args[i])")
            }
            i += 2
        }
        guard ["iso", "apple", "pq", "hlg", "sips"].contains(mode),
              [8, 10].contains(depth), scale.isFinite, (1...2).contains(scale),
              quality.isFinite, (0...1).contains(quality),
              ["rename", "skip", "overwrite"].contains(collision) else {
            throw failure("HEIC 输出参数无效。")
        }
        if let value = gainQuality {
            guard mode == "iso", value.isFinite, (0...1).contains(value) else {
                throw failure("独立增益图品质仅适用于 ISO HEIC，取值须为 0 到 1。")
            }
        }
    }
    var destination: URL {
        folder.appendingPathComponent(input.deletingPathExtension().lastPathComponent).appendingPathExtension("heic")
    }
}

func pathExists(_ url: URL) -> Bool {
    var info = stat()
    return url.path.withCString { lstat($0, &info) } == 0
}

func validateInput(_ request: ExportRequest) throws {
    guard let source = CGImageSourceCreateWithURL(request.input as CFURL, nil) else {
        throw failure("无法读取 Lightroom 渲染的中间文件。")
    }
    if request.mode == "sips" { return }
    guard CGImageSourceGetType(source) as String? == "public.tiff",
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
          let depth = properties[kCGImagePropertyDepth as String] as? NSNumber,
          depth.intValue >= 16,
          let image = CGImageSourceCreateImageAtIndex(source, 0,
            [kCGImageSourceShouldCache: false] as CFDictionary),
          let space = image.colorSpace else {
        throw failure("HDR 模式需要 Lightroom 渲染的 16 位或 32 位 HDR TIFF；请重新打开导出窗口。")
    }
    let floatLinear = depth.intValue == 32 && image.bitmapInfo.contains(.floatComponents) &&
        ((space.name as String? ?? "").lowercased().contains("linear") || CGColorSpaceUsesExtendedRange(space))
    guard CGColorSpaceUsesITUR_2100TF(space) || floatLinear else {
        throw failure("中间 TIFF 使用 SDR 色彩编码。请在照片中开启 HDR 编辑，并使用 HDR 色彩空间、开启 HDR 输出、关闭最大兼容。")
    }
}

func encode(_ request: ExportRequest, into folder: URL) throws -> URL {
    let process = Process()
    if request.mode == "sips" {
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
        process.arguments = ["-s", "format", "heic", "-s", "formatOptions",
            String(Int((request.quality * 100).rounded())), "-o",
            folder.appendingPathComponent(request.destination.lastPathComponent).path, request.input.path]
    } else {
        let binaryFolder = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.deletingLastPathComponent()
        process.executableURL = binaryFolder.appendingPathComponent("toGainMapHDR")
        var flags = [request.input.path, folder.path, "-q", String(request.quality)]
        switch request.mode {
        case "pq": flags += ["-p", "-d", "10"]
        case "hlg": flags += ["-h", "-d", "10"]
        case "apple": flags += ["-g", "-d", String(request.depth), "-H", String(request.scale)]
        default: flags += ["-d", String(request.depth), "-H", String(request.scale)]
        }
        if let quality = request.gainQuality { flags += ["-Q", String(quality)] }
        process.arguments = flags
    }
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    let log = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationReason == .exit && process.terminationStatus == 0 else {
        let detail = String(data: log, encoding: .utf8) ?? ""
        throw failure("HEIC 编码失败（\(process.terminationStatus)）。\n\(detail.suffix(4000))")
    }
    let output = folder.appendingPathComponent(request.destination.lastPathComponent)
    guard let source = CGImageSourceCreateWithURL(output as CFURL, nil) else {
        throw failure("编码程序未生成可读取的 HEIC，中间 TIFF 已保留。")
    }
    if request.mode == "iso" || request.mode == "apple" {
        let type = request.mode == "iso" ? kCGImageAuxiliaryDataTypeISOGainMap : kCGImageAuxiliaryDataTypeHDRGainMap
        guard CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, type) != nil else {
            throw failure("输出中没有预期的 HDR 增益图；照片可能未包含超出 SDR 范围的亮度。请检查 HDR 编辑。")
        }
    }
    if request.mode == "pq" || request.mode == "hlg" {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as NSDictionary?
        guard (properties?[kCGImagePropertyDepth] as? NSNumber)?.intValue == 10,
              let image = CGImageSourceCreateImageAtIndex(source, 0,
                [kCGImageSourceShouldCache: false] as CFDictionary),
              let space = image.colorSpace,
              request.mode == "pq" ? CGColorSpaceIsPQBased(space) : CGColorSpaceIsHLGBased(space) else {
            throw failure("直接 HDR 输出的位深或 PQ／HLG 编码不符合预期。")
        }
    }
    return output
}

// nil means skipped. RENAME_EXCL checks and publishes in one filesystem
// operation, so a concurrently created destination can never be overwritten.
func publish(_ staged: URL, request: ExportRequest) throws -> URL? {
    if request.collision == "overwrite" {
        guard request.destination.resolvingSymlinksInPath() != request.input.resolvingSymlinksInPath() else {
            throw failure("拒绝用输出覆盖输入原文件。")
        }
        let result = staged.path.withCString { from in
            request.destination.path.withCString { to in Darwin.rename(from, to) }
        }
        guard result == 0 else { throw failure("无法替换目标 HEIC：\(String(cString: strerror(errno)))") }
        return request.destination
    }
    for number in 1...10000 {
        let name = number == 1 ? request.destination.lastPathComponent :
            "\(request.destination.deletingPathExtension().lastPathComponent) (\(number)).heic"
        let candidate = request.folder.appendingPathComponent(name)
        let result = staged.path.withCString { from in
            candidate.path.withCString { to in renamex_np(from, to, UInt32(RENAME_EXCL)) }
        }
        if result == 0 { return candidate }
        let code = errno
        if code == EEXIST {
            if request.collision == "skip" { return nil }
            continue
        }
        throw failure("无法保存 HEIC：\(String(cString: strerror(code)))。已有文件未被覆盖。")
    }
    throw failure("同名文件过多，请更换输出名称。")
}

func run() throws -> Bool {
    let request = try ExportRequest(CommandLine.arguments)
    if request.collision == "skip" && pathExists(request.destination) {
        print("已跳过重名文件：\(request.destination.lastPathComponent)")
        return false
    }
    try validateInput(request)
    let stage = request.folder.appendingPathComponent(".heic-export-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700])
    defer { try? FileManager.default.removeItem(at: stage) }
    let encoded = try encode(request, into: stage)
    if let saved = try publish(encoded, request: request) {
        print("已保存：\(saved.path)")
        return true
    }
    print("已跳过重名文件：\(request.destination.lastPathComponent)")
    return false
}

do {
    exit(try run() ? 0 : 10)
} catch {
    FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
    exit(1)
}
