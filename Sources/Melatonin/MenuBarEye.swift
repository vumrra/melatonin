import AppKit

@MainActor
enum MenuBarEye {
  static func image(for enabled: Bool?, phase: Double = 0) -> NSImage {
    guard let enabled else {
      return NSImage(systemSymbolName: "questionmark.circle", accessibilityDescription: "상태 확인 중")!
    }
    let image = NSImage(size: NSSize(width: 22, height: 18), flipped: false) { _ in
      NSGraphicsContext.saveGraphicsState()
      let transform = NSAffineTransform()
      transform.translateX(by: 11 - 9 * 0.78, yBy: 9 - 9 * 0.78)
      transform.scale(by: 0.78)
      transform.concat()
      NSColor.black.setStroke()
      NSColor.black.setFill()
      let outline = NSBezierPath()
      outline.lineWidth = 1.5
      outline.lineCapStyle = .round
      outline.lineJoinStyle = .round
      if enabled {
        outline.move(to: NSPoint(x: 1, y: 9))
        outline.curve(
          to: NSPoint(x: 17, y: 9), controlPoint1: NSPoint(x: 5, y: 15),
          controlPoint2: NSPoint(x: 13, y: 15))
        outline.curve(
          to: NSPoint(x: 1, y: 9), controlPoint1: NSPoint(x: 13, y: 3),
          controlPoint2: NSPoint(x: 5, y: 3))
        outline.close()
        outline.stroke()
        NSBezierPath(ovalIn: NSRect(x: 6.5, y: 6.5, width: 5, height: 5)).fill()
      } else {
        outline.move(to: NSPoint(x: 1, y: 11))
        outline.curve(
          to: NSPoint(x: 17, y: 11), controlPoint1: NSPoint(x: 5, y: 5),
          controlPoint2: NSPoint(x: 13, y: 5))
        outline.stroke()
        for (x, y, dx) in [(4.0, 8.1, -1.3), (9.0, 6.5, 0.0), (14.0, 8.1, 1.3)] {
          let lash = NSBezierPath()
          lash.lineWidth = 1.5
          lash.lineCapStyle = .round
          lash.move(to: NSPoint(x: x, y: y))
          lash.line(to: NSPoint(x: x + dx, y: y - 2.7))
          lash.stroke()
        }
      }
      NSGraphicsContext.restoreGraphicsState()
      if enabled {
        for index in 0..<5 {
          let angle = phase + Double(index) * .pi * 2 / 5
          let diameter = index.isMultiple(of: 2) ? 1.5 : 1.1
          let x = 11 + cos(angle) * 9.8
          let y = 9 + sin(angle) * 7.2
          NSColor.black.withAlphaComponent(0.5 + Double(index) * 0.12).setFill()
          NSBezierPath(
            ovalIn: NSRect(
              x: x - diameter / 2, y: y - diameter / 2,
              width: diameter, height: diameter)
          ).fill()
        }
      }
      return true
    }
    image.isTemplate = true
    image.accessibilityDescription = enabled ? "눈 뜸 · 잠자기 방지 켜짐" : "눈 감음 · 잠자기 방지 꺼짐"
    return image
  }
}
