// swift-tools-version: 6.0

// The app builds with SwiftPM alone, so Xcode isn't needed. `make build` compiles the `Jots`
// executable and wraps it into Jots.app (see the Makefile).

import PackageDescription

let package = Package(
    name: "Jots",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Jots", targets: ["Jots"]),
        .library(name: "JotsCore", targets: ["JotsCore"]),
    ],
    targets: [
        .executableTarget(name: "Jots", dependencies: ["JotsCore"]),
        .target(name: "JotsCore"),
        .testTarget(name: "JotsCoreTests", dependencies: ["JotsCore"]),
    ]
)
