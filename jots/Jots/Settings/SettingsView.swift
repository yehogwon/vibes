import SwiftUI

struct SettingsView: View {
    @AppStorage(SettingsKey.fontFamily) private var fontFamily = EditorFontFamily.system
    @AppStorage(SettingsKey.fontSize) private var fontSize = 14.0
    @AppStorage(SettingsKey.hidesSyntax) private var hidesSyntax = true

    var body: some View {
        Form {
            Section("Editor") {
                Picker("Font", selection: $fontFamily) {
                    ForEach(EditorFontFamily.allCases) { family in
                        Text(family.label).tag(family)
                    }
                }
                LabeledContent("Size") {
                    Stepper(value: $fontSize, in: 10...28, step: 1) {
                        Text("\(Int(fontSize)) pt").monospacedDigit()
                    }
                }
                Toggle("Hide Markdown syntax outside the current line", isOn: $hidesSyntax)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize()
    }
}
