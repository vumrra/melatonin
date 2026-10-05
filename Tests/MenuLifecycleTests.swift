import AppKit

@main
struct MenuLifecycleTests {
  @MainActor static func main() {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)

    for index in 0..<42 {
      for time in [0.0, 0.25, 2.0, 60.0, 3600.0] {
        let point = AwakeParticle.sample(index: index, elapsed: time, reduceMotion: false)
        precondition(hypot(point.x, point.y) < 114, "Particles must stay inside the panel")
        precondition((0.3...0.901).contains(point.opacity), "Particle opacity must stay bounded")
        let still = AwakeParticle.sample(index: index, elapsed: time, reduceMotion: true)
        let origin = AwakeParticle.sample(index: index, elapsed: 0, reduceMotion: true)
        precondition(
          still.x == origin.x && still.y == origin.y, "Reduce Motion must freeze particles")
      }
    }
    let start = AwakeParticle.sample(index: 0, elapsed: 0, reduceMotion: false)
    let later = AwakeParticle.sample(index: 0, elapsed: 2, reduceMotion: false)
    precondition(start.x != later.x && start.y != later.y, "ON particles must actually move")
    let openEye = MenuBarEye.image(for: true)
    let closedEye = MenuBarEye.image(for: false)
    precondition(
      openEye.isTemplate && closedEye.isTemplate, "Menu icons must follow system contrast")
    precondition(
      openEye.tiffRepresentation != nil && closedEye.tiffRepresentation != nil,
      "Both icons must render")
    precondition(
      openEye.tiffRepresentation != closedEye.tiffRepresentation, "Open and closed eyes must differ"
    )
    print("PASS particle motion, bounds, Reduce Motion, and eye icon rendering")
    precondition(
      openEye.size == NSSize(width: 22, height: 18), "Eye orbit must fit the status item")
    precondition(
      openEye.tiffRepresentation != MenuBarEye.image(for: true, phase: 0.7).tiffRepresentation,
      "Particles must move around the open menu eye")
    precondition(
      closedEye.tiffRepresentation == MenuBarEye.image(for: false, phase: 0.7).tiffRepresentation,
      "Closed menu eye must remain still without particles")
    print("PASS menu eye orbit changes only when ON")

    func visiblePanels() -> [NSWindow] {
      app.windows.filter { $0 is MenuPanel && $0.isVisible }
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
      let windows = app.windows.map { "\(type(of: $0)): \($0.frame), visible=\($0.isVisible)" }
      FileHandle.standardError.write(
        Data(
          "Active: \(app.isActive)\nWindows: \(windows)\nScreens: \(NSScreen.screens.map { $0.frame })\n"
            .utf8))
      precondition(!visiblePanels().isEmpty, "Launching must display a nonzero-size control panel")
      precondition(
        visiblePanels().first?.frame.size == NSSize(width: 280, height: 280),
        "Only the compact control should remain")
      let panel = visiblePanels().first as! MenuPanel
      precondition(
        panel.presentation.isVisible, "Showing the panel must enable visible-only animation")
      print("PASS first launch displays control panel")
      delegate.perform(NSSelectorFromString("togglePanel"))
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        precondition(visiblePanels().isEmpty, "Menu click must dismiss the panel")
        precondition(!panel.presentation.isVisible, "Hidden panels must pause animation")
        _ = delegate.applicationShouldHandleReopen(app, hasVisibleWindows: false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
          precondition(!visiblePanels().isEmpty, "Reopening must show the dismissed panel")
          precondition(panel.presentation.isVisible, "Reopening must resume animation")
          print("PASS reopening restores dismissed panel")
          _ = delegate.applicationShouldHandleReopen(app, hasVisibleWindows: true)
          precondition(!visiblePanels().isEmpty, "Repeated reopen must not hide the panel")
          print("PASS repeated reopen keeps panel visible")
          app.terminate(nil)
        }
      }
    }
    app.run()
    withExtendedLifetime(delegate) {}
  }
}
