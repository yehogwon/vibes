import AppKit
import MomentsCore
import SwiftUI
import UniformTypeIdentifiers

/// Adds or edits a moment. Nothing is saved until Save.
struct MomentEditor: View {
    @Environment(AppState.self) private var app
    @State private var draft: Moment
    @FocusState private var isNameFocused: Bool
    @State private var emojiTarget = EmojiTarget()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The moment as editing began. Only what changed since is saved, so an edit arriving from
    /// another Mac meanwhile survives.
    let original: Moment
    let isNew: Bool

    init(moment: Moment, isNew: Bool) {
        _draft = State(initialValue: moment)
        original = moment
        self.isNew = isNew
    }

    private func save() {
        app.save(draft, editedFrom: isNew ? nil : original)
    }

    var body: some View {
        VStack(spacing: 0) {
            // A new moment's kind is in the picker right below, so the title doesn't repeat it.
            PageHeader(title: isNew ? "New Moment" : "Edit \(kindName)") {
                Button { app.route = .list } label: {
                    IconLabel(title: "Back", systemImage: "chevron.left")
                }
                .buttonStyle(.borderless)
                .padding(.leading, -4)
                .help("Back without saving (Esc)")
            } trailing: {
                Button("Save", action: save)
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .help("Save (⌘↩)")
            }
            if isNew {
                kindPicker
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            }
            form
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            if !isNew {
                Divider()
                Button("Delete \(kindName)", role: .destructive) { app.delete(draft.id) }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.red)
                    .font(.callout)
                    .padding(.vertical, 10)
            }
        }
    }

    private var kindName: String {
        switch draft.kind {
        case .life: "Birthday"
        case .progress: "Progress Bar"
        default: "D-Day"
        }
    }

    /// Only while adding: an existing moment keeps its kind. Switching starts the kind's own rows
    /// over and keeps the ones every kind has.
    private var kindPicker: some View {
        Picker(
            "Kind",
            selection: Binding {
                draft.kind
            } set: { kind in
                // Picking the kind already chosen mustn't reset its date.
                guard kind != draft.kind else { return }
                // The rows fade while the last one moves with the panel's edge, which resizes to
                // fit them on this same curve.
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) { draft.switchKind(to: kind) }
            }
        ) {
            Text("D-Day").tag(Moment.Kind.date)
                .help("Count down to a day, or up from one")
            Text("Progress").tag(Moment.Kind.progress)
                .help("Show how far along a day, week, year, or other span is")
            Text("Birthday").tag(Moment.Kind.life)
                .help("Count someone's age from the day they were born")
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.small)
    }

    private var form: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
            row("Name") {
                TextField(namePlaceholder, text: $draft.name)
                    .textFieldStyle(.roundedBorder)
                    .focused($isNameFocused)
                    .onSubmit(save)
                    .onAppear {
                        if isNew {
                            isNameFocused = true
                        }
                    }
            }
            row("Icon") { iconPicker }
            row("Color") { swatches }
            switch draft.kind {
            case .progress:
                row("Span") {
                    Picker("Span", selection: $draft.span) {
                        ForEach(Moment.Span.allCases, id: \.self) { span in
                            Text(Self.spanName(span)).tag(span)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                if draft.span == .custom {
                    row("Starts") { datePicker($draft.startDate) }
                    row("Ends") { datePicker($draft.endDate) }
                }
            case .life:
                row("Born") { datePicker($draft.date) }
                row("Remind") { reminderPicker }
            default:
                row("Date") { datePicker($draft.date) }
                row("Repeat") {
                    Picker("Repeat", selection: $draft.repeatCycle) {
                        ForEach(options(Moment.RepeatCycle.allCases, current: draft.repeatCycle), id: \.self) { cycle in
                            Text(Self.repeatName(cycle)).tag(cycle)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                row("Count in") {
                    Picker("Count in", selection: $draft.unit) {
                        ForEach(options(Moment.Unit.allCases, current: draft.unit), id: \.self) { unit in
                            Text(Self.unitName(unit)).tag(unit)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                row("Remind") { reminderPicker }
            }
            GridRow(alignment: .center) {
                labelColumnStrut
                Toggle("Show in the menu bar", isOn: $draft.inMenubar)
                    .toggleStyle(.checkbox)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .font(.callout)
        .controlSize(.small)
    }

    /// While adding, the labels of every kind's rows, out of sight, so the label column is
    /// always as wide as its widest and switching kinds doesn't shift the fields sideways.
    private var labelColumnStrut: some View {
        ZStack {
            if isNew {
                ForEach(["Span", "Starts", "Ends", "Born", "Date", "Repeat", "Count in", "Remind"], id: \.self) {
                    Text($0)
                }
            }
        }
        .hidden()
    }

    private func row<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        GridRow(alignment: .center) {
            Text(label)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var namePlaceholder: String {
        switch draft.kind {
        case .life: "Whose birthday?"
        case .progress: Self.spanName(draft.span)
        default: "What's the day?"
        }
    }

    // MARK: - Icon

    private var iconPicker: some View {
        HStack(spacing: 8) {
            Button(action: emojiTarget.pick) {
                Text(draft.emoji.isEmpty ? "Emoji…" : draft.emoji)
            }
            .background {
                EmojiReceiver(target: emojiTarget) { draft.emoji = $0 }
                    .frame(width: 1, height: 1)
                    .accessibilityHidden(true)
            }
            .accessibilityLabel("Emoji")
            .accessibilityValue(draft.emoji)
            .help("Pick from Emoji & Symbols")
            if !draft.emoji.isEmpty {
                removeButton("Remove Emoji", help: "Use the symbol instead") { draft.emoji = "" }
            }
            Button("Photo…", action: choosePhoto)
            if draft.imageData != nil {
                removeButton("Remove Photo", help: "Use the emoji or symbol instead") { draft.imageData = nil }
            }
        }
    }

    private func removeButton(_ title: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            IconLabel(title: title, systemImage: "xmark.circle.fill")
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .help(help)
    }

    private func choosePhoto() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.message = "Choose a photo for “\(draft.displayName)”"
        app.lowerPanel(true)
        defer { app.lowerPanel(false) }
        guard panel.runModal() == .OK, let url = panel.url, let image = NSImage(contentsOf: url),
            let data = PhotoCache.thumbnail(of: image)
        else { return }
        draft.imageData = data
    }

    /// One swatch per color, each a 20 pt target. The chosen one wears a ring, so the choice
    /// doesn't rest on color alone.
    private var swatches: some View {
        HStack(spacing: 1) {
            ForEach(options(Palette.swatches, current: draft.colorHex), id: \.self) { hex in
                let isSelected = draft.colorHex == hex
                Button {
                    draft.colorHex = hex
                } label: {
                    Circle()
                        .fill(Palette.color(hex: hex))
                        .frame(width: 14, height: 14)
                        .overlay {
                            if hex.isEmpty {
                                Image(systemName: "a")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .frame(width: 20, height: 20)
                        .overlay(Circle().strokeBorder(Color.primary.opacity(isSelected ? 0.6 : 0), lineWidth: 1.5))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(Palette.name(hex: hex))
                .accessibilityLabel(Palette.name(hex: hex))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }

    // MARK: - Dates and options

    /// A date picker that keeps whole days, as the start of the day picked.
    private func datePicker(_ date: Binding<Date>) -> some View {
        DatePicker(
            "",
            selection: Binding {
                date.wrappedValue
            } set: { picked in
                date.wrappedValue = Calendar.current.startOfDay(for: picked)
            },
            displayedComponents: .date
        )
        .labelsHidden()
        .datePickerStyle(.field)
        .fixedSize()
    }

    private var reminderPicker: some View {
        Picker("Remind", selection: $draft.remindDays) {
            ForEach(options([-1, 0, 1, 2, 3, 7, 14, 30], current: draft.remindDays), id: \.self) { days in
                Text(Self.reminderName(days)).tag(days)
            }
        }
        .labelsHidden()
        .fixedSize()
    }

    /// The standard choices, plus the current value if it's something else (another app may
    /// have written it), so the picker can show it.
    private func options<Value: Equatable>(_ standard: [Value], current: Value) -> [Value] {
        standard.contains(current) ? standard : standard + [current]
    }

    static func spanName(_ span: Moment.Span) -> String {
        switch span {
        case .day: "Today"
        case .week: "This Week"
        case .month: "This Month"
        case .quarter: "This Quarter"
        case .year: "This Year"
        case .custom: "Custom Dates"
        default: span.rawValue.capitalized
        }
    }

    static func repeatName(_ cycle: Moment.RepeatCycle) -> String {
        switch cycle.step?.component {
        case .day?: "Every Week"
        case .month?: "Every Month"
        case .year?: "Every Year"
        default: "Never"
        }
    }

    static func unitName(_ unit: Moment.Unit) -> String {
        switch unit {
        case .day: "Days"
        case .week: "Weeks and Days"
        case .month: "Months and Days"
        case .year: "Years, Months, and Days"
        default: unit.rawValue.capitalized
        }
    }

    static func reminderName(_ days: Int) -> String {
        switch days {
        case ..<0: "None"
        case 0: "On the Day"
        case 1: "1 Day Before"
        case 7: "1 Week Before"
        case 14: "2 Weeks Before"
        default: "\(days) Days Before"
        }
    }
}

// MARK: - Emoji

/// Opens the Emoji & Symbols viewer for the editor's emoji button. The viewer types into the key
/// window's first responder, so the button hands focus to an `EmojiReceiver` first.
@MainActor
final class EmojiTarget {
    fileprivate weak var view: EmojiTextView?

    func pick() {
        guard let view, let window = view.window else { return }
        window.makeFirstResponder(view)
        NSApp.orderFrontCharacterPalette(nil)
    }
}

/// An invisible text view that passes on the last character it's given, or an empty string for
/// Delete, and keeps none of it.
private struct EmojiReceiver: NSViewRepresentable {
    let target: EmojiTarget
    let onPick: (String) -> Void

    func makeNSView(context: Context) -> EmojiTextView {
        let view = EmojiTextView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
        view.isRichText = false
        view.isFieldEditor = true
        view.drawsBackground = false
        view.insertionPointColor = .clear
        view.focusRingType = .none
        view.setAccessibilityElement(false)
        return view
    }

    func updateNSView(_ view: EmojiTextView, context: Context) {
        view.onPick = onPick
        target.view = view
    }
}

fileprivate final class EmojiTextView: NSTextView {
    var onPick: (String) -> Void = { _ in }

    override func insertText(_ string: Any, replacementRange: NSRange) {
        let text = (string as? NSAttributedString)?.string ?? (string as? String) ?? ""
        if let last = text.last {
            onPick(String(last))
        }
    }

    override func deleteBackward(_ sender: Any?) {
        onPick("")
    }

    /// Only the emoji button focuses it, so Tab passes it by, and leaves it for the next control.
    override var canBecomeKeyView: Bool { false }

    override func insertTab(_ sender: Any?) {
        window?.selectNextKeyView(nil)
    }

    override func insertBacktab(_ sender: Any?) {
        window?.selectPreviousKeyView(nil)
    }
}
