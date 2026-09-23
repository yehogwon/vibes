import AppKit
import SwiftUI

/// SwiftUI wrapper around `MarkdownTextView`.
///
/// The text view owns the text while it's on screen and reports changes through `onChange`.
/// `text` is loaded when the view is created and again whenever `revision` changes, which is how
/// edits from elsewhere (another Mac, another app) reach the editor.
struct MarkdownEditor: NSViewRepresentable {
    var text: String
    var revision: Int
    var isEditable: Bool
    var theme: MarkdownTheme
    var onChange: (String) -> Void
    /// Called for Escape, which otherwise opens the completion list.
    var onCancel: () -> Void = {}

    final class Coordinator {
        var onChange: (String) -> Void
        var onCancel: () -> Void
        var revision = 0

        init(onChange: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
            self.onChange = onChange
            self.onCancel = onCancel
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onChange: onChange, onCancel: onCancel)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = MarkdownTextView(usingTextLayoutManager: true)
        textView.configure(theme: theme)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.setMarkdown(text)
        textView.isEditable = isEditable
        context.coordinator.revision = revision
        textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))

        let coordinator = context.coordinator
        textView.onTextChange = { coordinator.onChange($0) }
        textView.onCancel = { coordinator.onCancel() }

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        scrollView.documentView = textView

        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.onChange = onChange
        context.coordinator.onCancel = onCancel
        guard let textView = scrollView.documentView as? MarkdownTextView else { return }
        textView.apply(theme: theme)
        textView.isEditable = isEditable
        if revision != context.coordinator.revision {
            context.coordinator.revision = revision
            textView.applyExternalText(text)
        }
    }
}
