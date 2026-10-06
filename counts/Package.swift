// swift-tools-version: 6.2

// The app builds with SwiftPM: `./build.sh` compiles the `Counts` executable and wraps it into
// Counts.app. Xcode has to be installed, since the Command Line Tools lack SwiftUI's macro plugin,
// but it never opens.

import PackageDescription

let package = Package(
    name: "Counts",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Counts", targets: ["Counts"]),
        .library(name: "CountsCore", targets: ["CountsCore"]),
    ],
    targets: [
        .executableTarget(name: "Counts", dependencies: ["CountsCore"]),
        .target(name: "CountsCore"),
        .testTarget(name: "CountsCoreTests", dependencies: ["CountsCore"]),
    ]
)
