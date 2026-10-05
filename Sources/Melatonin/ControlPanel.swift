import AppKit
import MelatoninCore
import SwiftUI

@MainActor
final class PanelPresentation: ObservableObject {
  @Published var isVisible = false
  var reveal: (() -> Void)?
}

struct ControlPanel: View {
  @ObservedObject var controller: PowerController
  @ObservedObject var presentation: PanelPresentation
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.colorScheme) private var colorScheme
  @State private var hovered = false
  @State private var activatedAt = Date()
  @State private var failure: String?

  private var isOn: Bool { controller.enabled == true }
  private let violet = Color(red: 0.57, green: 0.40, blue: 1)

  var body: some View {
    ZStack {
      if isOn {
        TimelineView(
          .animation(minimumInterval: 1.0 / 30, paused: !presentation.isVisible || reduceMotion)
        ) { timeline in
          let elapsed = reduceMotion ? 0 : timeline.date.timeIntervalSince(activatedAt)
          AwakeField(elapsed: elapsed, reduceMotion: reduceMotion)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
      }
      Button {
        Task {
          if controller.enabled == nil {
            await controller.refresh()
          } else {
            await controller.toggle()
          }
          // Authorization can move focus away; return to the verified result.
          let notice = controller.notice
          presentation.reveal?()
          if controller.enabled == true && notice == nil { activatedAt = Date() }
          failure = notice
        }
      } label: {
        VStack(spacing: 13) {
          if controller.isBusy {
            ProgressView().controlSize(.regular).tint(isOn ? .white : .secondary)
              .frame(height: 38)
          } else {
            Image(systemName: controller.enabled == nil ? "arrow.clockwise" : "power")
              .font(.system(size: 38, weight: .light))
          }
          Text(controller.isBusy ? "•••" : controller.enabled == nil ? "—" : isOn ? "ON" : "OFF")
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .tracking(3)
        }
        .frame(width: 148, height: 148)
        .foregroundStyle(isOn ? Color.white : Color.primary.opacity(0.55))
        .background {
          Circle().fill(
            LinearGradient(
              colors: isOn
                ? [
                  Color(red: 0.70, green: 0.56, blue: 1), violet,
                  Color(red: 0.36, green: 0.26, blue: 0.82),
                ]
                : [Color.primary.opacity(0.045), Color.primary.opacity(0.085)],
              startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .overlay {
          Circle().strokeBorder(
            LinearGradient(
              colors: [
                .white.opacity(isOn ? 0.55 : 0.12), .clear, violet.opacity(isOn ? 0.7 : 0.08),
              ],
              startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
        }
        .shadow(color: isOn ? violet.opacity(0.38) : .clear, radius: hovered ? 27 : 20, y: 7)
        .contentShape(Circle())
      }
      .buttonStyle(PowerButtonStyle(reduceMotion: reduceMotion))
      .scaleEffect(hovered && !reduceMotion ? 1.035 : 1)
      .onHover { hovered = $0 }
      .disabled(controller.isBusy)
      .accessibilityLabel(
        controller.enabled == nil ? "시스템 상태 다시 확인" : isOn ? "잠자기 방지 끄기" : "잠자기 방지 켜기"
      )
      .accessibilityValue(controller.enabled == nil ? "상태 알 수 없음" : isOn ? "켜짐" : "꺼짐")
      .accessibilityHint("변경 시 macOS 관리자 인증이 필요합니다. 설정은 종료 후에도 유지됩니다.")
      .help("잠자기 방지 ON/OFF · 관리자 인증 필요 · 가방에 넣기 전 OFF · 종료해도 설정 유지")
      .contextMenu {
        Button("Melatonin 종료") { NSApp.terminate(nil) }
          .disabled(controller.isBusy)
      }
      .animation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.65), value: isOn)
      .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: hovered)
    }
    .frame(width: 280, height: 280)
    .background(
      colorScheme == .dark
        ? Color(red: 0.065, green: 0.058, blue: 0.09)
        : Color(red: 0.985, green: 0.98, blue: 1)
    )
    .onChange(of: isOn) { _, enabled in
      if enabled { activatedAt = Date() }
    }
    .alert(
      "Melatonin", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })
    ) {
      Button("확인", role: .cancel) { failure = nil }
    } message: {
      Text(failure ?? "")
    }
  }
}

private struct PowerButtonStyle: ButtonStyle {
  let reduceMotion: Bool
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed && !reduceMotion ? 0.93 : 1)
      .brightness(configuration.isPressed ? 0.06 : 0)
      .animation(
        reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.6),
        value: configuration.isPressed)
  }
}

// Deterministic motion avoids random allocations and state updates on every frame.
struct AwakeParticle {
  let x: Double
  let y: Double
  let diameter: Double
  let opacity: Double

  static func sample(index: Int, elapsed: Double, reduceMotion: Bool) -> AwakeParticle {
    let time = reduceMotion ? 0 : max(0, elapsed)
    let seed = Double(index)
    let phase = seed * 2.3999632297
    let angle = phase + time * (0.12 + Double(index % 5) * 0.035)
    let radius = 89 + Double(index % 7) * 3.2 + sin(time * 0.8 + phase) * 3
    return AwakeParticle(
      x: cos(angle) * radius, y: sin(angle) * radius,
      diameter: 1.4 + Double(index % 4) * 0.6,
      opacity: 0.3 + (sin(time * 1.2 + phase) + 1) * 0.3)
  }
}

struct AwakeField: View {
  let elapsed: Double
  let reduceMotion: Bool

  var body: some View {
    Canvas { context, size in
      let center = CGPoint(x: size.width / 2, y: size.height / 2)
      let violet = Color(red: 0.61, green: 0.43, blue: 1)
      let halo = CGRect(x: center.x - 120, y: center.y - 120, width: 240, height: 240)
      context.fill(
        Path(ellipseIn: halo),
        with: .radialGradient(
          Gradient(colors: [violet.opacity(0.32), violet.opacity(0.08), .clear]),
          center: center, startRadius: 65, endRadius: 120))
      for index in 0..<42 {
        let particle = AwakeParticle.sample(
          index: index, elapsed: elapsed, reduceMotion: reduceMotion)
        let point = CGPoint(x: center.x + particle.x, y: center.y + particle.y)
        let dot = CGRect(
          x: point.x - particle.diameter / 2, y: point.y - particle.diameter / 2,
          width: particle.diameter, height: particle.diameter)
        let color = index.isMultiple(of: 3) ? Color(red: 0.4, green: 0.77, blue: 1) : violet
        context.fill(
          Path(ellipseIn: dot.insetBy(dx: -2, dy: -2)),
          with: .color(color.opacity(particle.opacity * 0.10)))
        context.fill(Path(ellipseIn: dot), with: .color(color.opacity(particle.opacity)))
      }
      if !reduceMotion && elapsed >= 0 && elapsed < 0.85 {
        let progress = elapsed / 0.85
        let radius = 77 + progress * 50
        let ring = CGRect(
          x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        context.stroke(
          Path(ellipseIn: ring), with: .color(violet.opacity((1 - progress) * 0.6)), lineWidth: 1.5)
      }
    }
  }
}
