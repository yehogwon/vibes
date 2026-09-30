import AppKit

// Jots lives in the menu bar (LSUIElement), so it runs on an AppKit delegate instead of a SwiftUI
// `App`: its panel peeks open on hover and opens from the shortcut, which MenuBarExtra can't do.
let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
