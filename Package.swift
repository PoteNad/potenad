// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "PoteNad", platforms: [.macOS(.v13)],
  products: [.executable(name: "PoteNad", targets: ["PoteNad"])],
  targets: [
    .target(name: "TextCore"), .executableTarget(name: "PoteNad", dependencies: ["TextCore"]),
    .testTarget(name: "TextCoreTests", dependencies: ["TextCore"]),
  ])
