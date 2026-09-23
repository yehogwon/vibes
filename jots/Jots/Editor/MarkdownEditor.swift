import AppKit
import SwiftUI

/// SwiftUI wrapper around `MarkdownTextView`.
///
/// `text` is only read when the view is created: the text view owns the text while it is on
/// screen, and reports changes through `onChange`. Give the editor a new identity (`.id(...)`)
/// to load a different jot.
struct MarkdownEditor: NSViewRepresentable {
    var text: String
    var theme: MarkdownTheme
    var onChange: (String) -> Void

    final class Coordinator {
        var onChange: (String) -> Void

        init(onChange: @escaping (String) -> Void) {
            self.onChange = onChange
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onChange: onChange)
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
        textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))

        let coordinator = context.coordinator
        textView.onTextChange = { coordinator.onChange($0) }

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
        (scrollView.documentView as? MarkdownTextView)?.apply(theme: theme)
    }
}
