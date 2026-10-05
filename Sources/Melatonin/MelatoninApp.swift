import AppKit
import Combine
import MelatoninCore
import SwiftUI

#if PANEL_PREVIEW
  // A separate verification entry point: only app-owned rendering, no system writes.
  @main
  struct PanelPreview {
    private struct PreviewRunner: CommandRunning {
      let enabled: Bool
      func run(_ command: PowerCommand) async throws -> CommandResult {
        guard command == .read else { throw PreviewError.writeForbidden }
        return CommandResult(status: 0, output: "SleepDisabled \(enabled ? 1 : 0)")
      }
    }
    private enum PreviewError: Error { case writeForbidden, renderFailed }

    @MainActor static func main() async throws {
      _ = NSApplication.shared
      let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      func save(_ image: NSImage?, name: String) throws {
        guard let image, let tiff = image.tiffRepresentation,
          let data = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else { throw PreviewError.renderFailed }
        try data.write(to: directory.appendingPathComponent(name))
        print("Rendered \(name)")
      }
      for enabled in [false, true] {
        for dark in [false, true] {
          let controller = PowerController(runner: PreviewRunner(enabled: enabled))
          await controller.refresh()
          let view = ControlPanel(controller: controller, presentation: PanelPresentation())
            .environment(\.colorScheme, dark ? .dark : .light)
          let renderer = ImageRenderer(content: view)
          renderer.scale = 2
          try save(
            renderer.nsImage, name: "\(enabled ? "on" : "off")-\(dark ? "dark" : "light").png")
        }
        try save(MenuBarEye.image(for: enabled), name: enabled ? "eye-open.png" : "eye-closed.png")
      }
      let eyes = HStack(spacing: 32) {
        Image(nsImage: MenuBarEye.image(for: false)).resizable().frame(width: 72, height: 72)
        Image(nsImage: MenuBarEye.image(for: true)).resizable().frame(width: 72, height: 72)
      }.foregroundStyle(.black).padding(24).background(.white)
      try save(ImageRenderer(content: eyes).nsImage, name: "eye-pair.png")
      for elapsed in [0.0, 2.0] {
        let renderer = ImageRenderer(
          content: AwakeField(elapsed: elapsed, reduceMotion: false)
            .frame(width: 280, height: 280))
        renderer.scale = 2
        try save(renderer.nsImage, name: "particles-\(Int(elapsed)).png")
      }
    }
  }
#elseif !LIFECYCLE_TEST
  @main
  struct MelatoninApp {
    @MainActor static func main() {
      let app = NSApplication.shared
      let delegate = AppDelegate()
      app.delegate = delegate
      app.setActivationPolicy(.accessory)
      app.run()
      withExtendedLifetime(delegate) {}
    }
  }
#endif

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private let controller = PowerController()
  private var statusItem: NSStatusItem!
  private lazy var panel = MenuPanel(
    contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
  private var outsideClickMonitor: Any?
  private var observation: AnyCancellable?
  private var polling: Task<Void, Never>?
  private var eyeAnimation: Task<Void, Never>?
  private var motionObservation: AnyCancellable?

  func applicationDidFinishLaunching(_ notification: Notification) {
    let identifier = Bundle.main.bundleIdentifier ?? "app.melatonin.menu"
    guard NSRunningApplication.runningApplications(withBundleIdentifier: identifier).count <= 1
    else {
      NSApp.terminate(nil)
      return
    }
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    statusItem.button?.target = self
    statusItem.button?.action = #selector(togglePanel)
    panel.level = .floating
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.hidesOnDeactivate = false
    panel.isReleasedWhenClosed = false
    panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
    panel.presentation.reveal = { [weak self] in self?.showPanel() }
    let hostingController = NSHostingController(
      rootView:
        ControlPanel(controller: controller, presentation: panel.presentation))
    hostingController.sizingOptions = [.preferredContentSize]
    hostingController.view.wantsLayer = true
    hostingController.view.layer?.cornerRadius = 24
    hostingController.view.layer?.masksToBounds = true
    panel.contentViewController = hostingController
    panel.setContentSize(hostingController.view.fittingSize)
    // Mouse-only monitoring does not require Accessibility permission.
    outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [
      .leftMouseDown, .rightMouseDown,
    ]) { [weak self] _ in
      Task { @MainActor [weak self] in self?.panel.orderOut(nil) }
    }
    observation = controller.$enabled.removeDuplicates().sink { [weak self] enabled in
      self?.updateIcon(enabled)
    }
    motionObservation = NSWorkspace.shared.notificationCenter.publisher(
      for: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification
    ).sink { [weak self] _ in
      guard let self else { return }
      self.updateIcon(self.controller.enabled)
    }
    polling = Task { [weak self] in
      while !Task.isCancelled {
        guard let controller = self?.controller else { return }
        await controller.refresh()
        do { try await Task.sleep(for: .seconds(3)) } catch { return }
      }
    }
    DispatchQueue.main.async { [weak self] in self?.showPanel() }
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool
  {
    showPanel()
    return false
  }

  func applicationWillTerminate(_ notification: Notification) {
    polling?.cancel()
    eyeAnimation?.cancel()
    if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
    // Never reset the user's system power setting on exit.
  }

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    controller.isBusy ? .terminateCancel : .terminateNow
  }

  @objc private func togglePanel() {
    if panel.isVisible { panel.orderOut(nil) } else { showPanel() }
  }

  private func showPanel() {
    guard let button = statusItem?.button else { return }
    controller.clearNotice()
    Task { await controller.refresh() }
    if let screen = button.window?.screen ?? NSScreen.main {
      let available = screen.visibleFrame.insetBy(dx: 8, dy: 8)
      let anchor = button.window?.frame
      let anchorX =
        anchor.flatMap {
          $0.width > 0 && $0.minY >= screen.visibleFrame.maxY ? $0.midX : nil
        } ?? available.maxX
      let x = max(
        available.minX, min(anchorX - panel.frame.width / 2, available.maxX - panel.frame.width))
      panel.setFrameTopLeftPoint(NSPoint(x: x, y: available.maxY))
    }
    // Do not depend on a visible status-item anchor: it may be behind the notch.
    NSApp.activate(ignoringOtherApps: true)
    panel.makeKeyAndOrderFront(nil)
  }

  private func updateIcon(_ enabled: Bool?) {
    eyeAnimation?.cancel()
    eyeAnimation = nil
    let label = enabled.map { $0 ? "ON · 잠자기 방지 중" : "OFF · 정상 잠자기" } ?? "상태 확인 중"
    statusItem.button?.image = MenuBarEye.image(for: enabled)
    statusItem.button?.toolTip = "Melatonin · \(label)"
    statusItem.button?.setAccessibilityLabel("Melatonin · \(label)")
    guard enabled == true, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
      return
    }
    eyeAnimation = Task { [weak self] in
      while !Task.isCancelled {
        guard let self else { return }
        self.statusItem.button?.image = MenuBarEye.image(
          for: true, phase: ProcessInfo.processInfo.systemUptime * 0.8)
        do { try await Task.sleep(for: .milliseconds(83)) } catch { return }
      }
    }
  }
}

@MainActor
final class MenuPanel: NSPanel {
  let presentation = PanelPresentation()
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }
  override func makeKeyAndOrderFront(_ sender: Any?) {
    super.makeKeyAndOrderFront(sender)
    presentation.isVisible = isVisible
  }
  override func orderOut(_ sender: Any?) {
    presentation.isVisible = false
    super.orderOut(sender)
  }
  override func cancelOperation(_ sender: Any?) { orderOut(sender) }
}
