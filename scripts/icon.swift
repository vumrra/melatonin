import AppKit

let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
  for scale in [1, 2] {
    let pixels = size * scale
    let image = NSImage(size: NSSize(width: pixels, height: pixels))
    image.lockFocus()
    let side = CGFloat(pixels)
    let background = NSBezierPath(
      roundedRect: NSRect(x: side * 0.07, y: side * 0.07, width: side * 0.86, height: side * 0.86),
      xRadius: side * 0.20, yRadius: side * 0.20)
    NSColor(calibratedRed: 0.55, green: 0.46, blue: 0.98, alpha: 1).setFill()
    background.fill()
    let moon = NSBezierPath()
    moon.windingRule = .evenOdd
    moon.appendOval(
      in: NSRect(x: side * 0.25, y: side * 0.23, width: side * 0.51, height: side * 0.55))
    // Clip the cutout to the moon so the even-odd path cannot draw an extra disk.
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(
      ovalIn: NSRect(x: side * 0.25, y: side * 0.23, width: side * 0.51, height: side * 0.55)
    ).addClip()
    moon.appendOval(
      in: NSRect(x: side * 0.41, y: side * 0.37, width: side * 0.47, height: side * 0.49))
    NSColor.white.setFill()
    moon.fill()
    NSGraphicsContext.restoreGraphicsState()
    image.unlockFocus()
    let representation = NSBitmapImageRep(data: image.tiffRepresentation!)!
    let suffix = scale == 2 ? "@2x" : ""
    let url = directory.appendingPathComponent("icon_\(size)x\(size)\(suffix).png")
    try representation.representation(using: .png, properties: [:])!.write(to: url)
  }
}
