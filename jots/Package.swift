// swift-tools-version: 6.2

// The app builds with SwiftPM: `./build.sh` compiles the `Jots` executable and wraps it into
// Jots.app. Xcode has to be installed, since the Command Line Tools lack SwiftUI's macro plugin,
// but it never opens.

import PackageDescription

let package = Package(
    name: "Jots",
    platforms: [.macOS(.v26)],
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
