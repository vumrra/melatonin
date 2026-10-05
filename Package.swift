// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "Melatonin",
  platforms: [.macOS(.v14)],
  products: [.executable(name: "Melatonin", targets: ["Melatonin"])],
  targets: [
    .target(name: "MelatoninCore"),
    .executableTarget(name: "Melatonin", dependencies: ["MelatoninCore"]),
    // Command Line Tools do not ship XCTest/Testing. This executable also runs without Xcode.
    .executableTarget(
      name: "MelatoninCoreTests", dependencies: ["MelatoninCore"], path: "Tests/MelatoninCoreTests"),
  ]
)
