import Combine
import Foundation

public enum PowerCommand: Equatable, Sendable {
  case read
  case set(Bool)

  public var executable: String {
    switch self {
    case .read: "/usr/bin/pmset"
    case .set: "/usr/bin/osascript"
    }
  }

  public var arguments: [String] {
    switch self {
    case .read: ["-g"]
    case .set(let enabled):
      // Both scripts are fixed literals. Never interpolate user input into a root command.
      [
        "-e",
        enabled
          ? "do shell script \"/usr/bin/pmset -a disablesleep 1\" with administrator privileges"
          : "do shell script \"/usr/bin/pmset -a disablesleep 0\" with administrator privileges",
      ]
    }
  }
}

public struct CommandResult: Sendable {
  public let status: Int32
  public let output: String

  public init(status: Int32, output: String) {
    self.status = status
    self.output = output
  }
}

public protocol CommandRunning: Sendable {
  func run(_ command: PowerCommand) async throws -> CommandResult
}

public struct SystemCommandRunner: CommandRunning {
  public init() {}

  public func run(_ command: PowerCommand) async throws -> CommandResult {
    try await Task.detached(priority: .userInitiated) {
      let process = Process()
      let pipe = Pipe()
      process.executableURL = URL(fileURLWithPath: command.executable)
      process.arguments = command.arguments
      process.standardOutput = pipe
      process.standardError = pipe
      process.standardInput = FileHandle.nullDevice
      // Do not inherit shell hooks, PATH overrides, or injected dynamic-library settings.
      process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LANG": "en_US.UTF-8"]
      try process.run()
      let data = pipe.fileHandleForReading.readDataToEndOfFile()
      process.waitUntilExit()
      return CommandResult(
        status: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
    }.value
  }
}

public enum PowerStateParser {
  public static func parse(_ text: String) -> Bool? {
    let values = text.split(whereSeparator: \.isNewline).compactMap { line -> String? in
      let fields = line.split(whereSeparator: \.isWhitespace)
      guard fields.first == "SleepDisabled", fields.count == 2 else { return nil }
      return String(fields[1])
    }
    guard values.count == 1 else { return nil }
    switch values[0] {
    case "0": return false
    case "1": return true
    default: return nil
    }
  }
}

@MainActor
public final class PowerController: ObservableObject {
  @Published public private(set) var enabled: Bool?
  @Published public private(set) var isBusy = false
  @Published public private(set) var notice: String?
  private let runner: any CommandRunning
  private var isReading = false

  public init(runner: any CommandRunning = SystemCommandRunner()) {
    self.runner = runner
  }

  public func refresh() async {
    guard !isBusy, !isReading else { return }
    isReading = true
    defer { isReading = false }
    do {
      enabled = try await readState()
    } catch {
      enabled = nil
      notice = "시스템 상태를 확인하지 못했어요. 잠시 후 다시 시도해 주세요."
    }
  }

  public func toggle() async {
    guard !isBusy, !isReading, enabled != nil else { return }
    isBusy = true
    notice = nil
    defer { isBusy = false }
    do {
      // Re-read immediately before changing: another app or terminal may have changed it.
      let current = try await readState()
      enabled = current
      let target = !current
      let result = try await runner.run(.set(target))
      // Never infer success from the button click or the process exit code alone.
      enabled = try await readState()
      if result.status != 0 {
        notice =
          result.output.contains("(-128)")
          ? "인증을 취소했어요."
          : "macOS 인증 또는 명령 실행 중 오류가 발생했어요. 현재 표시된 상태를 확인해 주세요."
      } else if enabled != target {
        notice = "설정이 적용되지 않았어요. 다른 전원 관리 앱을 확인해 주세요."
      }
    } catch {
      enabled = nil
      notice = "시스템 상태를 확인하지 못했어요. 잠시 후 다시 시도해 주세요."
    }
  }

  public func clearNotice() { notice = nil }

  private func readState() async throws -> Bool {
    let result = try await runner.run(.read)
    guard result.status == 0, let state = PowerStateParser.parse(result.output) else {
      throw PowerError.unreadableState
    }
    return state
  }
}

private enum PowerError: Error {
  case unreadableState
}
