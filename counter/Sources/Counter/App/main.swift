import AppKit

// Counter lives in the menu bar (LSUIElement), so it runs on an AppKit delegate instead of a
// SwiftUI `App`: its panel peeks open on hover, which MenuBarExtra can't do.
let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
