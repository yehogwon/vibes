import AppKit
import MomentsCore
import SwiftUI
import UniformTypeIdentifiers

/// Adds or edits a moment. Nothing is saved until Save.
struct MomentEditor: View {
    @Environment(AppState.self) private var app
    @State private var draft: Moment
    @FocusState private var isNameFocused: Bool
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
            PageHeader(title: isNew ? "New \(kindName)" : "Edit \(kindName)") {
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
            row("") {
                Toggle("Show in the menu bar", isOn: $draft.inMenubar)
                    .toggleStyle(.checkbox)
            }
        }
        .font(.callout)
        .controlSize(.small)
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
            AvatarView(moment: draft, fraction: draft.kind == .progress ? 0.7 : nil, size: 26)
            TextField("🙂", text: emoji)
                .textFieldStyle(.roundedBorder)
                .frame(width: 44)
                .multilineTextAlignment(.center)
                .help("Type or pick an emoji (⌃⌘Space)")
            Button("Photo…", action: choosePhoto)
            if draft.imageData != nil {
                Button { draft.imageData = nil } label: {
                    IconLabel(title: "Remove Photo", systemImage: "xmark.circle.fill", side: 20)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Use the emoji or symbol instead")
            }
        }
    }

    /// Keeps only the last character typed, so the field holds one emoji.
    private var emoji: Binding<String> {
        Binding {
            draft.emoji
        } set: { text in
            draft.emoji = text.last.map(String.init) ?? ""
        }
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
