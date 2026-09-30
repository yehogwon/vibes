// swift-tools-version: 6.2

// The app builds with SwiftPM: `./build.sh` compiles the `Moments` executable and wraps it into
// Moments.app. Xcode has to be installed, since the Command Line Tools lack SwiftUI's macro plugin,
// but it never opens.

import PackageDescription

let package = Package(
    name: "Moments",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Moments", targets: ["Moments"]),
        .library(name: "MomentsCore", targets: ["MomentsCore"]),
    ],
    targets: [
        .executableTarget(name: "Moments", dependencies: ["MomentsCore"]),
        .target(name: "MomentsCore"),
        .testTarget(name: "MomentsCoreTests", dependencies: ["MomentsCore"]),
    ]
)
