import AppKit
import MomentsCore
import SwiftUI

/// The list of moments, in the order they were arranged.
struct MomentListPage: View {
    @Environment(AppState.self) private var app
    /// The list's natural height, so the scroll view can be exactly as tall as its rows up to a
    /// limit, and the panel only as tall as it needs to be.
    @State private var listHeight: CGFloat = 0
    @State private var drag: Drag?
    /// How far the pointer has moved since the row was picked up.
    @State private var dragTranslation: CGFloat = 0
    @State private var rowHeights: [UUID: CGFloat] = [:]
    /// The press on a row, from the moment it's held long enough to pick up. Resets however the
    /// gesture ends, even when it's cancelled, so the row is always put down.
    @GestureState private var press = Press.none
    /// The row last put down, and when, so the click that ends a hold doesn't also open it.
    @State private var putDown: (id: UUID, at: Date)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let maxListHeight: CGFloat = 470

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "Moments", subtitle: app.now.formatted(.dateTime.weekday(.wide).month(.wide).day())) {
                EmptyView()
            } trailing: {
                addButton
            }
            banners
            if app.store.moments.isEmpty {
                emptyState
            } else {
                list
            }
            Divider()
                .padding(.top, 4)
            footer
        }
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: Self.rowSpacing) {
                ForEach(app.store.moments) { moment in
                    let isLifted = drag?.id == moment.id
                    MomentRow(moment: moment, now: app.now)
                        .background {
                            // Lifted, the row sits above the ones it passes.
                            RoundedRectangle(cornerRadius: 10)
                                .fill(.background)
                                .shadow(color: Color(nsColor: .shadowColor).opacity(0.18), radius: 8, y: 2)
                                .opacity(isLifted ? 1 : 0)
                        }
                        .scaleEffect(isLifted ? 1.03 : 1)
                        .offset(y: offset(for: moment.id))
                        .zIndex(isLifted ? 1 : 0)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                            rowHeights[moment.id] = $0
                        }
                        // A click edits; holding picks the row up instead. They can't be one
                        // exclusive gesture, which never lets the click through, so the click
                        // skips a press that lifted the row.
                        .onTapGesture { clicked(moment) }
                        .simultaneousGesture(reorderGesture(for: moment.id))
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { app.edit(moment) }
                        .accessibilityAction(named: "Move Up") { app.move(moment.id, by: -1) }
                        .accessibilityAction(named: "Move Down") { app.move(moment.id, by: 1) }
                        .contextMenu { menu(for: moment) }
                }
            }
            .padding(.horizontal, 8)
            .coordinateSpace(name: Self.listSpace)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { listHeight = $0 }
        }
        .scrollIndicators(.automatic)
        .frame(height: min(max(listHeight, 1), Self.maxListHeight))
        .onChange(of: press) { _, press in
            switch press {
            case .held(let id, let translation): follow(id, translation: translation)
            case .none: drop()
            }
        }
    }

    /// Opens the moment, unless the click ended a hold that picked its row up. SwiftUI hands that
    /// click over while the row is still lifted; the time covers it arriving after it's put down.
    private func clicked(_ moment: Moment) {
        let justPutDown = putDown.map { $0.id == moment.id && Date.now.timeIntervalSince($0.at) < 0.25 } ?? false
        guard drag?.id != moment.id, !justPutDown else { return }
        app.edit(moment)
    }

    // MARK: - Reordering

    /// A row being dragged to a new place in the list.
    private struct Drag {
        var id: UUID
        /// Where the row started.
        var from: Int
        /// Where it lands if dropped now.
        var to: Int
    }

    private enum Press: Equatable {
        case none
        /// Held long enough to pick up, and moved `translation` since.
        case held(UUID, translation: CGFloat)
    }

    private static let rowSpacing: CGFloat = 2
    /// How long a row is held before it lifts, like a Finder or Dock long press.
    private static let holdDuration = 0.3
    private static let listSpace = "MomentList"

    /// The dragged row follows the pointer; the rows between where it started and where it
    /// would land move aside to make room for it.
    private func offset(for id: UUID) -> CGFloat {
        guard let drag else { return 0 }
        if id == drag.id { return dragTranslation }
        guard let index = app.store.moments.firstIndex(where: { $0.id == id }) else { return 0 }
        let room = (rowHeights[drag.id] ?? 0) + Self.rowSpacing
        if drag.from < index, index <= drag.to { return -room }
        if drag.to <= index, index < drag.from { return room }
        return 0
    }

    private func reorderGesture(for id: UUID) -> some Gesture {
        LongPressGesture(minimumDuration: Self.holdDuration)
            // Measured in the list, since the row itself moves with the pointer.
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.listSpace)))
            .updating($press) { value, press, _ in
                guard case .second(true, let drag) = value else { return }
                press = .held(id, translation: drag?.translation.height ?? 0)
            }
    }

    /// Lifts the row when it's first held, then keeps it under the pointer while the rows around
    /// it close the gap it left and open one where it would land.
    private func follow(_ id: UUID, translation: CGFloat) {
        let ids = app.store.moments.map(\.id)
        // Looked up each time, in case a change from another Mac moved the row.
        guard let from = ids.firstIndex(of: id) else { return }
        // The row tracks the pointer as is; only the rows around it animate.
        dragTranslation = translation
        guard let current = drag else {
            NSCursor.closedHand.push()
            withAnimation(liftAnimation) { drag = Drag(id: id, from: from, to: from) }
            return
        }
        let to = landing(from: from, in: ids)
        if to != current.to || from != current.from {
            withAnimation(shiftAnimation) { drag = Drag(id: id, from: from, to: to) }
        }
    }

    /// The index the dragged row lands at: past every row whose middle its middle has crossed.
    private func landing(from: Int, in ids: [UUID]) -> Int {
        var tops: [CGFloat] = []
        var top: CGFloat = 0
        for id in ids {
            tops.append(top)
            top += (rowHeights[id] ?? 0) + Self.rowSpacing
        }
        func middle(_ index: Int) -> CGFloat { tops[index] + (rowHeights[ids[index]] ?? 0) / 2 }
        let dragged = middle(from) + dragTranslation
        var to = from
        while to + 1 < ids.count, middle(to + 1) < dragged { to += 1 }
        while to > 0, middle(to - 1) > dragged { to -= 1 }
        return to
    }

    /// Puts the row in its new place. In the same animation it settles from under the pointer
    /// into its slot, while the rows that made room stay where they already are.
    private func drop() {
        guard let drag else { return }
        NSCursor.pop()
        putDown = (drag.id, .now)
        withAnimation(shiftAnimation) {
            var ids = app.store.moments.map(\.id)
            if drag.to != drag.from, let from = ids.firstIndex(of: drag.id) {
                ids.remove(at: from)
                let before = drag.to < ids.count ? ids[drag.to] : nil
                app.move(drag.id, before: before)
            }
            self.drag = nil
            dragTranslation = 0
        }
    }

    /// A quick pop, just springy enough to feel picked up.
    private var liftAnimation: Animation? {
        reduceMotion ? nil : .snappy(duration: 0.2)
    }

    private var shiftAnimation: Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.2)
    }

    @ViewBuilder
    private func menu(for moment: Moment) -> some View {
        Button("Edit…") { app.edit(moment) }
        Button(moment.inMenubar ? "Hide from Menu Bar" : "Show in Menu Bar") { app.toggleMenuBar(moment) }
        Divider()
        // Besides dragging, for people who can't or would rather not.
        Button("Move Up") { withAnimation(shiftAnimation) { app.move(moment.id, by: -1) } }
            .disabled(app.store.moments.first?.id == moment.id)
        Button("Move Down") { withAnimation(shiftAnimation) { app.move(moment.id, by: 1) } }
            .disabled(app.store.moments.last?.id == moment.id)
        Divider()
        Button("Delete", role: .destructive) { app.store.delete(moment.id) }
    }

    /// Opens the editor on a D-Day, as ⌘N does; the kind can be switched there.
    private var addButton: some View {
        Button { app.newMoment(.date) } label: {
            IconLabel(title: "Add Moment", systemImage: "plus")
                .font(.body.weight(.semibold))
        }
        .buttonStyle(.plain)
        .help("Add a moment (⌘N)")
        // The symbol, not its hit area, lines up with the panel's edge inset.
        .padding(.trailing, -4)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("Count down to the days that matter.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("New D-Day…") { app.newMoment(.date) }
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    @ViewBuilder
    private var banners: some View {
        if let notice = app.store.notice {
            Banner(systemImage: "info.circle", message: notice) { app.store.dismissNotice() }
        }
        if let error = app.store.lastError {
            Banner(systemImage: "exclamationmark.triangle.fill", symbolColor: .orange, message: error)
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            SyncStatusLabel(status: app.store.status)
            Spacer()
            Button { app.route = .settings } label: {
                IconLabel(title: "Settings", systemImage: "gearshape")
            }
            .help("Hover, login, and sync options (⌘,)")
        }
        .buttonStyle(.borderless)
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .padding(.leading, 16)
        .padding(.trailing, 12)
        .padding(.vertical, 4)
    }
}

struct SyncStatusLabel: View {
    var status: MomentStore.Status

    var body: some View {
        Label(text, systemImage: symbol)
            .help(help)
    }

    private var text: String {
        switch status {
        case .off: "On this Mac"
        case .connecting: "Connecting to iCloud…"
        case .synced: "Synced with iCloud"
        case .downloading: "Downloading from iCloud…"
        case .failed: "Couldn't sync"
        }
    }

    private var symbol: String {
        switch status {
        case .off: "laptopcomputer"
        case .connecting: "icloud"
        case .synced: "checkmark.icloud"
        case .downloading: "icloud.and.arrow.down"
        case .failed: "exclamationmark.icloud"
        }
    }

    private var help: String {
        switch status {
        case .synced(let date): "Last synced \(date.formatted(date: .omitted, time: .shortened))"
        case .failed(let message): message
        case .off: "Sign in to iCloud and turn on iCloud Drive to sync between Macs."
        default: ""
        }
    }
}
