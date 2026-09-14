// swift-tools-version: 6.0
import PackageDescription

// Some SwiftPM toolchains record the deployment target as the SDK version, which makes AppKit
// draw windows with older styling. The build scripts pass the real SDK version.
let linkSDK: [LinkerSetting] =
  Context.environment["POTENAD_SDK_VERSION"].map {
    [.unsafeFlags(["-Xlinker", "-platform_version", "-Xlinker", "macos", "-Xlinker", "13.0", "-Xlinker", $0])]
  } ?? []

let package = Package(
  name: "PoteNad", platforms: [.macOS(.v13)],
  products: [.executable(name: "PoteNad", targets: ["PoteNad"])],
  targets: [
    .target(name: "TextCore"),
    .executableTarget(name: "PoteNad", dependencies: ["TextCore"], linkerSettings: linkSDK),
    .testTarget(name: "TextCoreTests", dependencies: ["TextCore"]),
  ])
