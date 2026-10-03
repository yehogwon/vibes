import AppKit
import Carbon
import MomentsCore
import SwiftUI
import UniformTypeIdentifiers

/// Adds or edits a moment, under the moment as the list shows it. Edits to a moment are saved as
/// they're made; a new one is added with Add.
struct MomentEditor: View {
    @Environment(AppState.self) private var app
    @State private var draft: Moment
    /// The moment as last saved. Only what changed since is saved next, so an edit arriving from
    /// another Mac meanwhile survives.
    @State private var saved: Moment
    @FocusState private var isNameFocused: Bool
    @State private var emojiTarget = EmojiTarget()
    @State private var isAvatarHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let isNew: Bool
    /// Shared with the list, so the bar at the top moves up from the moment's row.
    let namespace: Namespace.ID

    init(moment: Moment, isNew: Bool, namespace: Namespace.ID) {
        _draft = State(initialValue: moment)
        _saved = State(initialValue: moment)
        self.isNew = isNew
        self.namespace = namespace
    }

    /// Saves the edits since the last save, unless the moment has been deleted meanwhile.
    private func save() {
        guard !isNew, draft != saved, app.store.moment(withID: draft.id) != nil else { return }
        app.store.save(draft, from: saved)
        saved = draft
    }

    /// Whether the edits not saved yet include typing, which is saved once it pauses rather than
    /// at every key: the file isn't rewritten each time, and a date isn't saved half-typed.
    private var isTyping: Bool {
        draft.name != saved.name || draft.date != saved.date || draft.startDate != saved.startDate
            || draft.endDate != saved.endDate
    }

    /// Edits that look half-done wait for the editor to close, rather than show in the menu bar: a
    /// name cleared to type another, or custom dates that end before they start.
    private var isHalfDone: Bool {
        (draft.name.allSatisfy(\.isWhitespace) && !saved.name.allSatisfy(\.isWhitespace))
            || (draft.kind == .progress && draft.span == .custom && draft.endDate < draft.startDate)
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
                .help(isNew ? "Back without adding (Esc)" : "Back to the list (Esc)")
            } trailing: {
                if isNew {
                    Button("Add") { app.add(draft) }
                        .keyboardShortcut(.return, modifiers: .command)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .help("Add to the list (⌘↩)")
                }
            }
            MomentRow(moment: draft, now: app.now, isFocused: true) { avatarButton }
                .modifier(MovesBetweenPages(id: draft.id, namespace: namespace))
                .padding(.horizontal, 8)
                // With the row's own inset, 16 pt to the fields.
                .padding(.bottom, 10)
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
        .task(id: draft) {
            if isTyping {
                try? await Task.sleep(for: .seconds(1))
            }
            guard !Task.isCancelled, !isHalfDone else { return }
            save()
        }
        // Leaving the editor saves whatever's left, half-done or not.
        .onAppear { app.saveEditor = save }
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
                    .onSubmit { isNew ? app.add(draft) : save() }
                    .onAppear {
                        if isNew {
                            isNameFocused = true
                        }
                    }
            }
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

    /// The bar's picture. A click picks an emoji; a right-click also offers a photo, or clearing
    /// both for the kind's own symbol.
    private var avatarButton: some View {
        Button(action: emojiTarget.pick) {
            AvatarView(moment: draft, now: app.now)
                // A ring under the pointer, since nothing else says the picture is a button.
                .overlay(Circle().strokeBorder(Color.primary.opacity(isAvatarHovered ? 0.3 : 0), lineWidth: 1.5))
                .onHover { isAvatarHovered = $0 }
                .animation(.easeOut(duration: 0.12), value: isAvatarHovered)
        }
        .buttonStyle(.plain)
        .background {
            EmojiReceiver(target: emojiTarget) { emoji in
                draft.emoji = emoji
                // A photo wins over the emoji in `AvatarView`, so it would hide the one picked.
                if !emoji.isEmpty {
                    draft.imageData = nil
                }
            }
            .frame(width: 1, height: 1)
            .accessibilityHidden(true)
            .onDisappear(perform: emojiTarget.close)
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { emojiTarget.buttonSize = $0 }
        .contextMenu {
            Button("Choose Emoji…", action: emojiTarget.pick)
            Button("Choose Photo…", action: choosePhoto)
            if draft.imageData != nil || !draft.emoji.isEmpty {
                Divider()
                Button("Clear Icon") {
                    draft.emoji = ""
                    draft.imageData = nil
                }
            }
        }
        .accessibilityLabel("Icon")
        .accessibilityValue(draft.imageData != nil ? "Photo" : draft.emoji)
        .accessibilityAction(named: "Choose Photo", choosePhoto)
        .help("Choose an emoji, or Control-click for a photo")
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
///
/// The viewer closes itself on Esc, but stays up through clicks in the app, even ones that move
/// focus. So while it's open, a click anywhere else in the app closes it, as a click away from a
/// text field does, and a click on the button closes it, as a click in the field does.
@MainActor
final class EmojiTarget {
    fileprivate weak var view: EmojiTextView?
    /// The emoji button's size. The receiver sits at its center.
    var buttonSize = CGSize.zero
    private var clickMonitor: Any?

    func pick() {
        guard let view, let window = view.window else { return }
        if clickMonitor != nil, Self.isViewerOpen {
            return close()
        }
        window.makeFirstResponder(view)
        // The text view's input context takes over only once this click is handled. Asked for
        // sooner, the viewer can open loose, away from the button, or not at all.
        DispatchQueue.main.async { NSApp.orderFrontCharacterPalette(nil) }
        guard clickMonitor == nil else { return }
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) {
            [weak self] event in
            MainActor.assumeIsolated {
                guard let self, !self.isOnButton(event) else { return }
                self.close()
            }
            return event
        }
    }

    /// Closes the viewer, if the button opened it, and lets go of keyboard focus, so what's typed
    /// next doesn't become the emoji.
    func close() {
        guard let clickMonitor else { return }
        NSEvent.removeMonitor(clickMonitor)
        self.clickMonitor = nil
        if let viewer = Self.viewer {
            TISDeselectInputSource(viewer)
        }
        if let view, view.window?.firstResponder === view {
            view.window?.makeFirstResponder(nil)
        }
    }

    private func isOnButton(_ event: NSEvent) -> Bool {
        guard let view, event.window === view.window else { return false }
        let point = view.convert(event.locationInWindow, from: nil)
        return abs(point.x - view.bounds.midX) <= buttonSize.width / 2
            && abs(point.y - view.bounds.midY) <= buttonSize.height / 2
    }

    /// The input source behind the viewer. It's selected while the viewer is open, and deselecting
    /// it is the one way to close the viewer: neither taking focus from its text view nor asking
    /// the input context closes it.
    private static var viewer: TISInputSource? {
        let filter = [kTISPropertyInputSourceID as String: "com.apple.CharacterPaletteIM"] as CFDictionary
        return (TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource])?.first
    }

    /// Whether the viewer is still open. It closes itself on Esc, which the app never sees.
    private static var isViewerOpen: Bool {
        guard let viewer, let selected = TISGetInputSourceProperty(viewer, kTISPropertyInputSourceIsSelected) else {
            return false
        }
        return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(selected).takeUnretainedValue())
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
