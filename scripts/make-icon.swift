import AppKit

let sourceURL = URL(fileURLWithPath: "Assets/PoteNad-Liquid.png")
guard let source = NSImage(contentsOf: sourceURL) else {
  fatalError("Could not load \(sourceURL.path)")
}

let directory = URL(fileURLWithPath: "build/PoteNad.iconset")
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

var images: [Int: Data] = [:]

for size in [16, 32, 128, 256, 512] {
  for scale in [1, 2] {
    let pixels = size * scale
    let bitmap = NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
      samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
      bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSGraphicsContext.current?.imageInterpolation = .high
    source.draw(
      in: NSRect(x: 0, y: 0, width: pixels, height: pixels),
      from: NSRect(x: 0, y: 0, width: source.size.width, height: source.size.height),
      operation: .copy,
      fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    let suffix = scale == 2 ? "@2x" : ""
    let data = bitmap.representation(using: .png, properties: [:])!
    images[pixels] = data
    try data.write(to: directory.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
  }
}

func bigEndianData(_ value: Int) -> Data {
  var value = UInt32(value).bigEndian
  return Data(bytes: &value, count: MemoryLayout<UInt32>.size)
}

var chunks = Data()
for (type, pixels) in [
  ("icp4", 16), ("icp5", 32), ("icp6", 64), ("ic07", 128), ("ic08", 256),
  ("ic09", 512), ("ic10", 1024), ("ic11", 32), ("ic12", 64), ("ic13", 256),
  ("ic14", 512),
] {
  let image = images[pixels]!
  chunks.append(Data(type.utf8))
  chunks.append(bigEndianData(image.count + 8))
  chunks.append(image)
}

var icon = Data("icns".utf8)
icon.append(bigEndianData(chunks.count + 8))
icon.append(chunks)
try icon.write(to: URL(fileURLWithPath: "Assets/PoteNad.icns"))
