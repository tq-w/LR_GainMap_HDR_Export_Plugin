import Foundation
import CoreImage
let root = URL(fileURLWithPath: CommandLine.arguments[1])
let context = CIContext()
let sdr = CIImage(color: CIColor(red: 0.5, green: 0.4, blue: 0.3))
    .cropped(to: CGRect(x: 0, y: 0, width: 128, height: 128))
try context.writeTIFFRepresentation(of: sdr, to: root.appendingPathComponent("sdr.tif"),
    format: .RGBA16, colorSpace: CGColorSpace(name: CGColorSpace.displayP3)!, options: [:])
try context.writeJPEGRepresentation(of: sdr, to: root.appendingPathComponent("sdr.jpg"),
    colorSpace: CGColorSpace(name: CGColorSpace.displayP3)!, options: [:])
let hdr = CIImage(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]), options: [.expandToHDR: true])!
    .transformed(by: CGAffineTransform(scaleX: 8, y: 8))
try context.writeTIFFRepresentation(of: hdr, to: root.appendingPathComponent("large-hdr.tif"),
    format: .RGBA16, colorSpace: CGColorSpace(name: CGColorSpace.displayP3_PQ)!, options: [:])
