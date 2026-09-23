import AppKit

// Jots lives in the menu bar (LSUIElement), so it runs on an AppKit delegate instead of a SwiftUI
// `App`: NSStatusItem + NSPopover can be opened from code, which MenuBarExtra can't.
let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
