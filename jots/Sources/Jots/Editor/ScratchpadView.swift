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
        MarkdownEditor(
            text: app.file.text, revision: app.file.externalRevision, isEditable: app.isEditable, theme: theme,
            onChange: { text in
                app.file.stage(text)
                updateStats(for: text, after: .milliseconds(250))
            },
            onCancel: { app.closeScratchpad() }
        )
        .safeAreaInset(edge: .top, spacing: 0) { banners }
        .safeAreaInset(edge: .bottom, spacing: 0) { footer }
        .onAppear { updateStats(for: app.file.text, after: .zero) }
        .onChange(of: app.copiedAt) { _, _ in flashCopied() }
    }

    private var theme: MarkdownTheme {
        MarkdownTheme(family: fontFamily, size: CGFloat(fontSize), hidesSyntax: hidesSyntax)
    }

    @ViewBuilder
    private var banners: some View {
        VStack(spacing: 0) {
            if app.file.isAwaitingDownload {
                Banner(systemImage: "icloud.and.arrow.down", message: "Downloading your scratchpad from iCloud…")
            }
            if let notice = app.storageNotice {
                Banner(systemImage: "info.circle", message: notice) {
                    Button("OK") { app.dismissStorageNotice() }
                }
            }
            if let copy = app.file.conflictCopies.last {
                let count = app.file.conflictCopies.count
                Banner(
                    systemImage: "exclamationmark.triangle",
                    message: count == 1
                        ? "Another Mac edited at the same time, so its version was kept as “\(copy.lastPathComponent)”."
                        : "\(count) versions edited at the same time were kept as separate files."
                ) {
                    Button("Show") { app.reveal(copy) }
                    Button("OK") { app.file.dismissConflicts() }
                }
            }
        }
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
            Button("Copy All", systemImage: "doc.on.doc") { app.copy() }
                .labelStyle(.iconOnly)
                .help("Copy everything (⇧⌘C)")
            Menu {
                Button("Export as Markdown…") { app.export() }
                Button("Show in Finder") { app.showInFinder() }
                Divider()
                Button("Settings…") {
                    app.closeScratchpad()
                    app.showSettings()
                }
                Button("Quit Jots") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("More")
        }
        .buttonStyle(.borderless)
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

/// A one-line notice above the editor.
private struct Banner<Actions: View>: View {
    var systemImage: String
    var message: String
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
            Text(message)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            actions
        }
        .font(.callout)
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }
}

extension Banner where Actions == EmptyView {
    init(systemImage: String, message: String) {
        self.init(systemImage: systemImage, message: message) { EmptyView() }
    }
}
