import Foundation
import ImageIO
import CoreGraphics
import CoreVideo

// ImageIO ignores the usual quality key on auxiliary images. Encode the scalar
// gain values as a neutral 8-bit HEIC with an explicit quality, then transplant
// only that image's item graph. The SDR codestream and ISO tmap bytes stay intact.
// ImageIO's public standalone encoder uses YCbCr 4:2:0; the repeated RGB channels
// carry one scalar map, with the original single-channel ISO parameters.
private func mapError(_ detail: String) -> NSError {
    NSError(domain: "GainMapCompression", code: 1,
        userInfo: [NSLocalizedDescriptionKey: "ISO 增益图压缩失败：" + detail])
}

private struct BMFFReader {
    let bytes: Data
    var position = 0
    mutating func read(_ count: Int) throws -> Data {
        guard count >= 0, position <= bytes.count, count <= bytes.count - position else {
            throw mapError("容器数据不完整。")
        }
        defer { position += count }
        return bytes.subdata(in: position..<position + count)
    }
    mutating func number(_ count: Int) throws -> Int {
        guard (0...8).contains(count) else { throw mapError("容器整数长度不支持。") }
        var value: UInt64 = 0
        for b in try read(count) { value = (value << 8) | UInt64(b) }
        guard value <= UInt64(Int.max) else { throw mapError("容器整数溢出。") }
        return Int(value)
    }
}

private func integer(_ value: Int, _ count: Int) throws -> Data {
    guard value >= 0, count > 0, count <= 8,
          count == 8 || UInt64(value) < (UInt64(1) << (count * 8)) else {
        throw mapError("容器字段超出范围。")
    }
    return Data((0..<count).reversed().map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) })
}

private struct BMFFBox {
    let type: String
    var payload: Data
    var encoded: Data {
        get throws {
            try integer(payload.count + 8, 4) + Data(type.utf8) + payload
        }
    }
}

private func boxes(_ bytes: Data) throws -> [BMFFBox] {
    var r = BMFFReader(bytes: bytes), result: [BMFFBox] = []
    while r.position < bytes.count {
        let start = r.position
        var size = try r.number(4)
        let type = String(decoding: try r.read(4), as: UTF8.self)
        if size == 1 { size = try r.number(8) }
        if size == 0 { size = bytes.count - start }
        guard size >= r.position - start else { throw mapError("容器区块长度无效。") }
        result.append(BMFFBox(type: type, payload: try r.read(size - (r.position - start))))
    }
    return result
}

private func joined(_ values: [BMFFBox]) throws -> Data {
    try values.reduce(into: Data()) { $0.append(try $1.encoded) }
}

private struct ItemReference {
    let type: String
    let from: Int
    let to: [Int]
}

private struct HEICContainer {
    let prefix: [BMFFBox]
    var meta: [BMFFBox]
    var info: [Int: BMFFBox] = [:]
    var payload: [Int: Data] = [:]
    var methods: [Int: Int] = [:]
    var references: [ItemReference] = []
    var properties: [BMFFBox] = []
    var associations: [Int: [(Int, Bool)]] = [:]
    var primary = 0

    init(_ data: Data) throws {
        let top = try boxes(data)
        guard top.filter({$0.type == "meta"}).count == 1,
              top.filter({$0.type == "ftyp"}).count == 1,
              top.allSatisfy({["ftyp", "meta", "mdat", "free"].contains($0.type)}),
              let metadata = top.first(where: {$0.type == "meta"}),
              metadata.payload.prefix(4) == Data(repeating: 0, count: 4) else {
            throw mapError("不支持该 HEIC 容器结构。")
        }
        prefix = top.filter {$0.type != "meta" && $0.type != "mdat"}
        meta = try boxes(Data(metadata.payload.dropFirst(4)))
        func required(_ name: String) throws -> Data {
            guard meta.filter({$0.type == name}).count == 1, let b = meta.first(where: {$0.type == name}) else {
                throw mapError("容器缺少或重复 \(name)。")
            }
            return b.payload
        }
        var p = BMFFReader(bytes: try required("pitm"))
        let pv = try p.number(1); _ = try p.read(3)
        guard pv <= 1 else { throw mapError("不支持该主图索引版本。") }
        primary = try p.number(pv == 0 ? 2 : 4)
        var inf = BMFFReader(bytes: try required("iinf"))
        let iv = try inf.number(1); _ = try inf.read(3)
        guard iv == 0 else { throw mapError("不支持该图像索引版本。") }
        let count = try inf.number(2)
        let entries = try boxes(try inf.read(inf.bytes.count - inf.position))
        guard entries.count == count else { throw mapError("图像索引计数不一致。") }
        for entry in entries {
            var r = BMFFReader(bytes: entry.payload)
            guard entry.type == "infe", try r.number(1) == 2 else { throw mapError("不支持该图像项版本。") }
            _ = try r.read(3)
            let id = try r.number(2)
            guard info[id] == nil else { throw mapError("图像项重复。") }
            info[id] = entry
        }
        let idat = meta.first(where: {$0.type == "idat"})?.payload ?? Data()
        var loc = BMFFReader(bytes: try required("iloc"))
        let version = try loc.number(1); _ = try loc.read(3)
        guard version <= 1 else { throw mapError("不支持该图像位置版本。") }
        let sizes = try loc.number(1), baseSizes = try loc.number(1)
        let offsetSize = sizes >> 4, lengthSize = sizes & 15, baseSize = baseSizes >> 4
        let indexSize = version == 1 ? baseSizes & 15 : 0
        for _ in 0..<(try loc.number(2)) {
            let id = try loc.number(2)
            let method = version == 1 ? try loc.number(2) : 0
            guard method <= 1, try loc.number(2) == 0 else { throw mapError("不支持外部图像数据。") }
            let base = try loc.number(baseSize), extents = try loc.number(2)
            var content = Data()
            for _ in 0..<extents {
                if indexSize > 0 { _ = try loc.number(indexSize) }
                let offset = try loc.number(offsetSize), length = try loc.number(lengthSize)
                let source = method == 0 ? data : idat
                guard base <= source.count, offset <= source.count - base,
                      length <= source.count - base - offset else { throw mapError("图像数据超出文件范围。") }
                content.append(source.subdata(in: base + offset..<base + offset + length))
            }
            guard payload[id] == nil else { throw mapError("图像位置重复。") }
            payload[id] = content; methods[id] = method
        }
        guard Set(info.keys) == Set(payload.keys) else { throw mapError("图像索引与数据不一致。") }
        if let iref = meta.first(where: {$0.type == "iref"}) {
            var r = BMFFReader(bytes: iref.payload)
            guard try r.number(4) == 0 else { throw mapError("不支持该引用版本。") }
            for ref in try boxes(try r.read(r.bytes.count - r.position)) {
                var rr = BMFFReader(bytes: ref.payload)
                let from = try rr.number(2), n = try rr.number(2)
                var to: [Int] = []
                for _ in 0..<n { to.append(try rr.number(2)) }
                references.append(ItemReference(type: ref.type, from: from, to: to))
            }
        }
        let iprp = try boxes(try required("iprp"))
        guard iprp.count == 2, let ipco = iprp.first(where: {$0.type == "ipco"}),
              let ipma = iprp.first(where: {$0.type == "ipma"}) else { throw mapError("不支持该图像属性结构。") }
        properties = try boxes(ipco.payload)
        var a = BMFFReader(bytes: ipma.payload)
        let av = try a.number(1), flags = try a.number(3)
        guard av == 0, flags <= 1 else { throw mapError("不支持该属性索引版本。") }
        for _ in 0..<(try a.number(4)) {
            let id = try a.number(2), n = try a.number(1)
            var values: [(Int, Bool)] = []
            for _ in 0..<n {
                let v = try a.number(flags == 0 ? 1 : 2), mask = flags == 0 ? 0x80 : 0x8000
                guard v & (mask - 1) <= properties.count else { throw mapError("属性引用超出范围。") }
                values.append((v & (mask - 1), v & mask != 0))
            }
            associations[id] = values
        }
    }

    func graph(_ root: Int) throws -> Set<Int> {
        var found: Set<Int> = [], visiting: Set<Int> = []
        func visit(_ id: Int) throws {
            guard info[id] != nil, !visiting.contains(id) else { throw mapError("图像依赖无效。") }
            if found.contains(id) { return }
            visiting.insert(id)
            let entry = info[id]!
            let kind = String(decoding: entry.payload.dropFirst(8).prefix(4), as: UTF8.self)
            guard kind == "grid" || kind == "hvc1" else { throw mapError("增益图不是 HEVC 图像。") }
            for ref in references where ref.from == id {
                guard ref.type == "dimg" else { throw mapError("增益图包含不支持的额外引用。") }
                for target in ref.to { try visit(target) }
            }
            visiting.remove(id); found.insert(id)
        }
        try visit(root)
        return found
    }

    mutating func replaceGainMap(with donor: HEICContainer) throws {
        let recipes = references.filter {$0.type == "dimg" && $0.to.count == 2 && $0.to.contains(primary) &&
            String(decoding: info[$0.from]?.payload.dropFirst(8).prefix(4) ?? Data(), as: UTF8.self) == "tmap"}
        guard recipes.count == 1, let root = recipes[0].to.first(where: {$0 != primary}) else {
            throw mapError("无法定位唯一的 ISO 增益图。")
        }
        let old = try graph(root), replacement = try donor.graph(donor.primary)
        guard !old.contains(primary), references.allSatisfy({ref in
            old.contains(ref.from) || ref.to.allSatisfy {!old.contains($0) || $0 == root}
        }) else { throw mapError("增益图与其他图像共享数据。") }
        // Item IDs and entity group IDs share one namespace in ImageIO.
        var maximum = info.keys.max() ?? 0
        if let groups = meta.first(where: {$0.type == "grpl"}) {
            for group in try boxes(groups.payload) {
                var reader = BMFFReader(bytes: group.payload)
                _ = try reader.read(4)
                maximum = max(maximum, try reader.number(4))
            }
        }
        var next = maximum + 1
        var ids = [donor.primary: root]
        for id in replacement.sorted() where id != donor.primary { ids[id] = next; next += 1 }
        guard next <= 65536, properties.count + donor.properties.count < 32768 else {
            throw mapError("图像项或属性过多。")
        }
        for id in old { info.removeValue(forKey: id); payload.removeValue(forKey: id); associations.removeValue(forKey: id); methods.removeValue(forKey: id) }
        references.removeAll {old.contains($0.from)}
        let propertyOffset = properties.count
        properties += donor.properties
        for id in replacement {
            let target = ids[id]!
            var entry = donor.info[id]!
            entry.payload.replaceSubrange(4..<6, with: try integer(target, 2))
            entry.payload[3] |= 1 // Auxiliary roots must remain hidden, like their tiles.
            info[target] = entry; payload[target] = donor.payload[id]; methods[target] = donor.methods[id]
            associations[target] = donor.associations[id, default: []].map {
                ($0.0 == 0 ? 0 : $0.0 + propertyOffset, $0.1)
            }
        }
        references += donor.references.filter {replacement.contains($0.from)}.map {
            ItemReference(type: $0.type, from: ids[$0.from]!, to: $0.to.map {ids[$0]!})
        }
    }

    func encoded() throws -> Data {
        let ids = info.keys.sorted()
        let iinf = BMFFBox(type: "iinf", payload: try Data(repeating: 0, count: 4) + integer(ids.count, 2) + joined(ids.map {info[$0]!}))
        let refs = try references.map {ref in
            BMFFBox(type: ref.type, payload: try integer(ref.from, 2) + integer(ref.to.count, 2) + ref.to.reduce(into: Data()) {$0.append(try integer($1, 2))})
        }
        let iref = BMFFBox(type: "iref", payload: try Data(repeating: 0, count: 4) + joined(refs))
        var associationData = try integer(1, 4) + integer(associations.count, 4) // version 0, 16-bit associations
        for id in associations.keys.sorted() {
            let values = associations[id]!
            associationData.append(try integer(id, 2) + integer(values.count, 1))
            for (index, essential) in values { associationData.append(try integer(index | (essential ? 0x8000 : 0), 2)) }
        }
        let iprp = BMFFBox(type: "iprp", payload: try joined([
            BMFFBox(type: "ipco", payload: try joined(properties)), BMFFBox(type: "ipma", payload: associationData)]))
        func location(_ start: Int) throws -> BMFFBox {
            var d = try integer(0x01000000, 4) + integer(0x44, 1) + integer(0, 1) + integer(ids.count, 2)
            var offset = start, internalOffset = 0
            for id in ids {
                let content = payload[id]!
                let method = methods[id]!
                d.append(try integer(id, 2) + integer(method, 2) + integer(0, 2) + integer(1, 2) + integer(method == 0 ? offset : internalOffset, 4) + integer(content.count, 4))
                if method == 0 { offset += content.count } else { internalOffset += content.count }
            }
            return BMFFBox(type: "iloc", payload: d)
        }
        func metadata(_ start: Int) throws -> BMFFBox {
            var result: [BMFFBox] = []
            for b in meta where b.type != "idat" {
                switch b.type {
                case "iinf": result.append(iinf)
                case "iref": result.append(iref)
                case "iprp": result.append(iprp)
                case "iloc": result.append(try location(start))
                default: result.append(b)
                }
            }
            result.append(BMFFBox(type: "idat", payload: ids.filter {methods[$0] == 1}.reduce(into: Data()) {$0.append(payload[$1]!)}))
            return BMFFBox(type: "meta", payload: try Data(repeating: 0, count: 4) + joined(result))
        }
        let prefixData = try joined(prefix)
        let start = prefixData.count + (try metadata(0).encoded).count + 8
        let media = ids.filter {methods[$0] == 0}.reduce(into: Data()) {$0.append(payload[$1]!)}
        return try prefixData + metadata(start).encoded + BMFFBox(type: "mdat", payload: media).encoded
    }
}

func compressISOGainMap(_ encoded: Data, auxiliary: [String: Any]? = nil, quality: Double) throws -> Data {
    guard quality.isFinite, (0...1).contains(quality),
          let source = CGImageSourceCreateWithData(encoded as CFData, nil),
          let aux = auxiliary ?? (CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, kCGImageAuxiliaryDataTypeISOGainMap) as? [String: Any]),
          let desc = aux[kCGImageAuxiliaryDataInfoDataDescription as String] as? [String: Any],
          let bytes = aux[kCGImageAuxiliaryDataInfoData as String] as? Data,
          let width = desc["Width"] as? Int, let height = desc["Height"] as? Int,
          let row = desc["BytesPerRow"] as? Int,
          let format = desc["PixelFormat"] as? NSNumber,
          format.uint32Value == kCVPixelFormatType_OneComponent8,
          width > 0, height > 0, row >= width, height <= bytes.count / row,
          width <= Int.max / 4 / height else { throw mapError("缺少有效的单通道增益图。") }
    var rgb = Data(count: width * height * 4)
    rgb.withUnsafeMutableBytes { destination in bytes.withUnsafeBytes { source in
        let src = source.bindMemory(to: UInt8.self), dst = destination.bindMemory(to: UInt8.self)
        for y in 0..<height { for x in 0..<width {
            let value = src[y * row + x], p = (y * width + x) * 4
            dst[p] = value; dst[p + 1] = value; dst[p + 2] = value; dst[p + 3] = 255
        } }
    } }
    guard let provider = CGDataProvider(data: rgb as CFData),
          let image = CGImage(width: width, height: height, bitsPerComponent: 8,
            bitsPerPixel: 32, bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else {
        throw mapError("无法准备增益图像素。")
    }
    let donorData = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(donorData, "public.heic" as CFString, 1, nil) else {
        throw mapError("无法创建增益图编码器。")
    }
    CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { throw mapError("增益图编码未完成。") }
    var container = try HEICContainer(encoded)
    try container.replaceGainMap(with: HEICContainer(donorData as Data))
    let result = try container.encoded()
    guard let check = CGImageSourceCreateWithData(result as CFData, nil),
          let saved = CGImageSourceCopyAuxiliaryDataInfoAtIndex(check, 0, kCGImageAuxiliaryDataTypeISOGainMap) as? [String: Any],
          let savedDesc = saved[kCGImageAuxiliaryDataInfoDataDescription as String] as? [String: Any],
          (savedDesc["Width"] as? Int) == width, (savedDesc["Height"] as? Int) == height else {
        throw mapError("输出增益图读取或尺寸校验失败。")
    }
    return result
}
