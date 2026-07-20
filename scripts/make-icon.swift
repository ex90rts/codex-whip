import AppKit
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 4 else {
    fputs("Usage: make-icon.swift <source-png> <iconset-directory> <output-icns>\n", stderr)
    exit(64)
}

let sourceURL = URL(fileURLWithPath: arguments[1])
let outputDirectory = URL(fileURLWithPath: arguments[2], isDirectory: true)
let icnsURL = URL(fileURLWithPath: arguments[3])
guard let sourceImage = NSImage(contentsOf: sourceURL) else {
    fputs("Could not load \(sourceURL.path)\n", stderr)
    exit(1)
}

let representations: [(name: String, size: Int, icnsType: String)] = [
    ("icon_16x16.png", 16, "icp4"),
    ("icon_16x16@2x.png", 32, "ic11"),
    ("icon_32x32.png", 32, "icp5"),
    ("icon_32x32@2x.png", 64, "ic12"),
    ("icon_128x128.png", 128, "ic07"),
    ("icon_128x128@2x.png", 256, "ic13"),
    ("icon_256x256.png", 256, "ic08"),
    ("icon_256x256@2x.png", 512, "ic14"),
    ("icon_512x512.png", 512, "ic09"),
    ("icon_512x512@2x.png", 1024, "ic10")
]

try FileManager.default.createDirectory(
    at: outputDirectory,
    withIntermediateDirectories: true
)

var iconChunks = Data()

for representation in representations {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: representation.size,
        pixelsHigh: representation.size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        fputs("Could not allocate \\(representation.name)\n", stderr)
        exit(1)
    }

    NSGraphicsContext.saveGraphicsState()
    guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        fputs("Could not create graphics context\n", stderr)
        exit(1)
    }
    NSGraphicsContext.current = context
    NSColor.white.setFill()
    NSBezierPath.fill(
        NSRect(x: 0, y: 0, width: representation.size, height: representation.size)
    )
    sourceImage.draw(
        in: NSRect(x: 0, y: 0, width: representation.size, height: representation.size),
        from: .zero,
        operation: .sourceOver,
        fraction: 1
    )
    NSGraphicsContext.restoreGraphicsState()
    // Keep an alpha channel so iconutil accepts the PNGs while the image
    // remains visually a solid white canvas.
    bitmap.setColor(
        NSColor(calibratedWhite: 1, alpha: 0.999),
        atX: 0,
        y: 0
    )

    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        fputs("Could not encode \(representation.name)\n", stderr)
        exit(1)
    }
    try png.write(to: outputDirectory.appendingPathComponent(representation.name))
    iconChunks.append(Data(representation.icnsType.utf8))
    iconChunks.append(bigEndianData(UInt32(png.count + 8)))
    iconChunks.append(png)
}

var icns = Data("icns".utf8)
icns.append(bigEndianData(UInt32(iconChunks.count + 8)))
icns.append(iconChunks)
try icns.write(to: icnsURL)

private func bigEndianData(_ value: UInt32) -> Data {
    var encoded = value.bigEndian
    return withUnsafeBytes(of: &encoded) { Data($0) }
}
