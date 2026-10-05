import Foundation
import MelatoninCore

private func expect(
  _ condition: Bool, _ message: String, file: StaticString = #file, line: UInt = #line
) {
  guard condition else { fatalError(message, file: file, line: line) }
}

private func state(_ enabled: Bool) -> CommandResult {
  CommandResult(
    status: 0,
    output:
      "System-wide power settings:\n SleepDisabled\t\t\(enabled ? 1 : 0)\nCurrently in use:\n sleep 1\n"
  )
}

private actor FakeRunner: CommandRunning {
  private var results: [CommandResult]
  private(set) var commands: [PowerCommand] = []
  init(_ results: [CommandResult]) { self.results = results }
  func run(_ command: PowerCommand) throws -> CommandResult {
    commands.append(command)
    guard !results.isEmpty else { throw Failure.noResult }
    return results.removeFirst()
  }
  enum Failure: Error { case noResult }
}

private actor PausingRunner: CommandRunning {
  private var continuation: CheckedContinuation<CommandResult, Never>?
  private(set) var commands: [PowerCommand] = []
  func run(_ command: PowerCommand) async -> CommandResult {
    commands.append(command)
    if case .set = command {
      return await withCheckedContinuation { continuation = $0 }
    }
    return state(false)
  }
  var isWaiting: Bool { continuation != nil }
  func finish() {
    continuation?.resume(returning: CommandResult(status: 1, output: "(-128)"))
    continuation = nil
  }
}

@main
struct PowerControlTests {
  @MainActor static func main() async throws {
    expect(PowerStateParser.parse(state(true).output) == true, "Parse ON")
    expect(PowerStateParser.parse(state(false).output) == false, "Parse OFF")
    for invalid in [
      "", "sleep 0", "SleepDisabled 2", "SleepDisabled true", "SleepDisabled 1 extra",
      "NotSleepDisabled 1", "SleepDisabled 0\nSleepDisabled 1", "SleepDisabled", "disablesleep 1",
    ] {
      expect(PowerStateParser.parse(invalid) == nil, "Reject invalid state: \(invalid)")
    }
    print("PASS exact parser and malformed states")

    expect(PowerCommand.read.executable == "/usr/bin/pmset", "Absolute read executable")
    expect(PowerCommand.read.arguments == ["-g"], "Read-only arguments")
    for enabled in [true, false] {
      let command = PowerCommand.set(enabled)
      expect(command.executable == "/usr/bin/osascript", "Absolute authorization executable")
      expect(
        command.arguments == [
          "-e",
          "do shell script \"/usr/bin/pmset -a disablesleep \(enabled ? 1 : 0)\" with administrator privileges",
        ], "Fixed privileged command")
    }
    print("PASS fixed, absolute privileged commands")

    let ok = CommandResult(status: 0, output: "")
    let failed = CommandResult(status: 1, output: "")
    let cancelled = CommandResult(status: 1, output: "User canceled. (-128)")
    let denied = CommandResult(status: 1, output: "Not authorized (-60005)")
    struct Scenario {
      let name: String
      let results: [CommandResult]
      let commands: [PowerCommand]
      let enabled: Bool?
      let notice: String?
      var toggle = true
    }
    let scenarios: [Scenario] = [
      .init(
        name: "startup preserves existing ON", results: [state(true)], commands: [.read],
        enabled: true, notice: nil, toggle: false),
      .init(
        name: "enable and verify", results: [state(false), state(false), ok, state(true)],
        commands: [.read, .read, .set(true), .read], enabled: true, notice: nil),
      .init(
        name: "disable and verify", results: [state(true), state(true), ok, state(false)],
        commands: [.read, .read, .set(false), .read], enabled: false, notice: nil),
      .init(
        name: "cancel authorization", results: [state(true), state(true), cancelled, state(true)],
        commands: [.read, .read, .set(false), .read], enabled: true, notice: "취소"),
      .init(
        name: "deny authorization", results: [state(false), state(false), denied, state(false)],
        commands: [.read, .read, .set(true), .read], enabled: false, notice: "인증 또는"),
      .init(
        name: "cancellation with externally changed state",
        results: [state(false), state(false), cancelled, state(true)],
        commands: [.read, .read, .set(true), .read], enabled: true, notice: "취소"),
      .init(
        name: "command error with target-state readback",
        results: [state(false), state(false), failed, state(true)],
        commands: [.read, .read, .set(true), .read], enabled: true, notice: "오류"),
      .init(
        name: "verify despite successful exit",
        results: [state(false), state(false), ok, state(false)],
        commands: [.read, .read, .set(true), .read], enabled: false, notice: "적용되지"),
      .init(
        name: "toggle uses fresh external state",
        results: [state(false), state(true), ok, state(false)],
        commands: [.read, .read, .set(false), .read], enabled: false, notice: nil),
      .init(
        name: "unknown state blocks mutation", results: [ok], commands: [.read], enabled: nil,
        notice: "확인하지"),
      .init(
        name: "nonzero read exit rejects output",
        results: [CommandResult(status: 1, output: state(true).output)], commands: [.read],
        enabled: nil, notice: "확인하지"),
      .init(
        name: "preflight failure blocks mutation", results: [state(false), failed],
        commands: [.read, .read], enabled: nil, notice: "확인하지"),
      .init(
        name: "failed readback shows unknown", results: [state(false), state(false), ok, failed],
        commands: [.read, .read, .set(true), .read], enabled: nil, notice: "확인하지"),
      .init(
        name: "process launch error handled", results: [], commands: [.read], enabled: nil,
        notice: "확인하지"),
      .init(
        name: "authorization process launch error handled", results: [state(false), state(false)],
        commands: [.read, .read, .set(true)], enabled: nil, notice: "확인하지"),
    ]
    for scenario in scenarios {
      let runner = FakeRunner(scenario.results)
      let controller = PowerController(runner: runner)
      await controller.refresh()
      if scenario.toggle { await controller.toggle() }
      expect(controller.enabled == scenario.enabled, "\(scenario.name): actual state")
      expect(!controller.isBusy, "\(scenario.name): clears busy")
      expect(await runner.commands == scenario.commands, "\(scenario.name): command sequence")
      if let notice = scenario.notice {
        expect(controller.notice?.contains(notice) == true, "\(scenario.name): error notice")
        expect(
          controller.notice?.contains("변경하지") == false,
          "\(scenario.name): no unverified no-change claim")
      } else {
        expect(controller.notice == nil, "\(scenario.name): no false error")
      }
      print("PASS \(scenario.name)")
    }

    let runner = FakeRunner([state(false), state(true)])
    let controller = PowerController(runner: runner)
    await controller.refresh()
    await controller.refresh()
    expect(controller.enabled == true, "Polling detects external change")
    expect(await runner.commands == [.read, .read], "Polling does not write")
    print("PASS polling detects external change without writing")

    let pausing = PausingRunner()
    let busyController = PowerController(runner: pausing)
    await busyController.refresh()
    let first = Task { await busyController.toggle() }
    for _ in 0..<10000 {
      if await pausing.isWaiting { break }
      await Task.yield()
    }
    expect(await pausing.isWaiting, "Authorization reached suspended state")
    expect(busyController.isBusy, "Busy while authorizing")
    await busyController.toggle()
    await busyController.refresh()
    expect(
      await pausing.commands == [.read, .read, .set(true)],
      "No repeated mutation or overlapping polling")
    await pausing.finish()
    await first.value
    expect(!busyController.isBusy, "Busy cleared after cancellation")
    expect(
      await pausing.commands == [.read, .read, .set(true), .read],
      "Final readback after cancellation")
    print("PASS repeated clicks and polling cannot race authorization")

    let result = try await SystemCommandRunner().run(.read)
    expect(result.status == 0, "Real pmset read exit")
    expect(PowerStateParser.parse(result.output) != nil, "Real pmset output parses")
    print("PASS real system read (no mutation)")
    print("All 20 test groups passed. No live power settings were changed.")
  }
}
