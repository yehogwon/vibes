// swift-tools-version: 6.0

// Dev tooling only: pins the formatter/linter so local runs and CI use the exact same version.
// Build with `swift build -c release --package-path Tools --product swift-format`.

import PackageDescription

let package = Package(
    name: "Tools",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-format.git", exact: "604.0.0")
    ],
    targets: []
)
