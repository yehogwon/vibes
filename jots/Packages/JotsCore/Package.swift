// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "JotsCore",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "JotsCore", targets: ["JotsCore"])
    ],
    targets: [
        .target(name: "JotsCore"),
        .testTarget(name: "JotsCoreTests", dependencies: ["JotsCore"]),
    ]
)
