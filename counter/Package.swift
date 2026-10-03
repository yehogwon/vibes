// swift-tools-version: 6.2

// The app builds with SwiftPM: `./build.sh` compiles the `Counter` executable and wraps it into
// Counter.app. Xcode has to be installed, since the Command Line Tools lack SwiftUI's macro plugin,
// but it never opens.

import PackageDescription

let package = Package(
    name: "Counter",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Counter", targets: ["Counter"]),
        .library(name: "CounterCore", targets: ["CounterCore"]),
    ],
    targets: [
        .executableTarget(name: "Counter", dependencies: ["CounterCore"]),
        .target(name: "CounterCore"),
        .testTarget(name: "CounterCoreTests", dependencies: ["CounterCore"]),
    ]
)
