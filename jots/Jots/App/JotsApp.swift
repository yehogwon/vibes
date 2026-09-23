import SwiftUI

@main
struct JotsApp: App {
    @State private var app = AppState()

    var body: some Scene {
        Window("Jots", id: "main") {
            ScratchpadView()
                .environment(app)
        }
        .defaultSize(width: 760, height: 640)
        .commands {
            FileCommands(app: app)
            FormatCommands()
        }

        Settings {
            SettingsView()
        }
    }
}
