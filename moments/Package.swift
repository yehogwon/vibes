// swift-tools-version: 6.2

// The app builds with SwiftPM: `./build.sh` compiles the `Moments` executable and its widgets
// (`MomentsWidgets`) and wraps them into Moments.app. Xcode has to be installed, since the Command
// Line Tools lack SwiftUI's macro plugin, but it never opens.

import PackageDescription

let package = Package(
    name: "Moments",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Moments", targets: ["Moments"]),
        .executable(name: "MomentsWidgets", targets: ["MomentsWidgets"]),
        .library(name: "MomentsCore", targets: ["MomentsCore"]),
    ],
    targets: [
        .executableTarget(name: "Moments", dependencies: ["MomentsCore", "MomentsUI"]),
        // An app extension, built the way Xcode builds one.
        .executableTarget(
            name: "MomentsWidgets", dependencies: ["MomentsCore", "MomentsUI"],
            // Limited to the API extensions may use.
            swiftSettings: [.unsafeFlags(["-application-extension"])],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-application_extension"]),
                // Starts in NSExtensionMain, which sets the extension up before handing over to the
                // @main WidgetBundle. Started at its own main, the extension crashes on launch.
                .unsafeFlags(["-Xlinker", "-e", "-Xlinker", "_NSExtensionMain"]),
            ]),
        .target(name: "MomentsCore"),
        // How a moment looks, in the app and in its widgets.
        .target(name: "MomentsUI", dependencies: ["MomentsCore"]),
        .testTarget(name: "MomentsCoreTests", dependencies: ["MomentsCore"]),
    ]
)
