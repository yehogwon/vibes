import JotsCore
import SwiftUI

struct ScratchpadView: View {
    @Environment(AppState.self) private var app
    @AppStorage(SettingsKey.fontFamily) private var fontFamily = EditorFontFamily.system
    @AppStorage(SettingsKey.fontSize) private var fontSize = 14.0
    @AppStorage(SettingsKey.hidesSyntax) private var hidesSyntax = true

    @State private var stats = TextStats()
    @State private var statsTask: Task<Void, Never>?
    @State private var showsCopied = false

    var body: some View {
        MarkdownEditor(text: app.file.text, theme: theme) { text in
            app.file.stage(text)
            updateStats(for: text, after: .milliseconds(250))
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { footer }
        .navigationTitle("Jots")
        .toolbar {
            ToolbarItemGroup {
                Button("Copy", systemImage: "doc.on.doc") { app.copy() }
                    .help("Copy everything (⇧⌘C)")
                Button("Export", systemImage: "square.and.arrow.up") { app.export() }
                    .help("Save a copy as a Markdown file (⇧⌘E)")
            }
        }
        .onAppear { updateStats(for: app.file.text, after: .zero) }
        .onChange(of: app.copiedAt) { _, _ in flashCopied() }
    }

    private var theme: MarkdownTheme {
        MarkdownTheme(family: fontFamily, size: CGFloat(fontSize), hidesSyntax: hidesSyntax)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Text(
                "\(stats.words) \(stats.words == 1 ? "word" : "words") · \(stats.characters) \(stats.characters == 1 ? "character" : "characters")"
            )
            .monospacedDigit()
            if let error = app.file.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .lineLimit(1)
                    .help(error)
            }
            Spacer()
            if showsCopied {
                Label("Copied", systemImage: "checkmark")
                    .transition(.opacity)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private func updateStats(for text: String, after delay: Duration) {
        statsTask?.cancel()
        statsTask = Task {
            if delay > .zero {
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
            }
            // Counting walks every character; keep it off the main thread for long text.
            let counted = await Task.detached(priority: .utility) { TextStats(counting: text) }.value
            guard !Task.isCancelled else { return }
            stats = counted
        }
    }

    private func flashCopied() {
        withAnimation { showsCopied = true }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation { showsCopied = false }
        }
    }
}
