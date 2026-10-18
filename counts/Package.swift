// swift-tools-version: 6.2

// The app builds with SwiftPM: `./build.sh` compiles the `Counts` executable and its widgets
// (`CountsWidgets`) and wraps them into Counts.app. Xcode has to be installed, since the Command
// Line Tools lack SwiftUI's macro plugin, but it never opens.

import PackageDescription

let package = Package(
    name: "Counts",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Counts", targets: ["Counts"]),
        .executable(name: "CountsWidgets", targets: ["CountsWidgets"]),
        .library(name: "CountsCore", targets: ["CountsCore"]),
    ],
    targets: [
        .executableTarget(name: "Counts", dependencies: ["CountsCore"]),
        // An app extension, built the way Xcode builds one.
        .executableTarget(
            name: "CountsWidgets", dependencies: ["CountsCore"],
            // Limited to the API extensions may use.
            swiftSettings: [.unsafeFlags(["-application-extension"])],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-application_extension"]),
                // Starts in NSExtensionMain, which sets the extension up before handing over to the
                // @main WidgetBundle. Started at its own main, the extension crashes on launch.
                .unsafeFlags(["-Xlinker", "-e", "-Xlinker", "_NSExtensionMain"]),
            ]),
        .target(name: "CountsCore"),
        .testTarget(name: "CountsCoreTests", dependencies: ["CountsCore"]),
    ]
)
