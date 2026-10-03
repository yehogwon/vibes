import MomentsCore
import SwiftUI

/// Everything the panel shows: the list, the editor, or settings. It reports its natural height
/// so the panel can follow it.
struct PanelView: View {
    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var moments
    var onHeightChange: (CGFloat) -> Void

    var body: some View {
        Group {
            switch app.route {
            case .list:
                MomentListPage(namespace: moments)
            case .editor(let moment, let isNew):
                MomentEditor(moment: moment, isNew: isNew, namespace: moments)
                    .id(moment.id)
            case .settings:
                SettingsPage()
            }
        }
        .transition(.opacity.animation(.easeInOut(duration: 0.15)))
        // Carries a moment's row up to the top of the editor and back down, while the pages fade.
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: app.route)
        .frame(width: PanelController.width)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { onHeightChange($0) }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

/// Moves a moment from where the last page showed it to where this one does: from its row in the
/// list to the top of the editor, and back. With Reduce Motion on, it only fades with the page.
struct MovesBetweenPages: ViewModifier {
    var id: UUID
    var namespace: Namespace.ID
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content.matchedGeometryEffect(id: id, in: namespace)
        }
    }
}

/// The top of each page: a title and its controls.
struct PageHeader<Leading: View, Trailing: View>: View {
    var title: String
    var subtitle: String?
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 8) {
            leading
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.headline)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            trailing
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }
}

/// A short notice, e.g. that an unreadable file was set aside. Its text starts at the panel's
/// edge inset, like everything else.
struct Banner: View {
    var systemImage: String
    /// Warnings color their symbol; the text stays legible in the label colors.
    var symbolColor: Color = .secondary
    var message: String
    var dismiss: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(symbolColor)
            Text(message)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let dismiss {
                Button("OK", action: dismiss)
                    .controlSize(.small)
            }
        }
        .font(.callout)
        .padding(8)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }
}

/// An icon-only button's label, with a hit area bigger than its symbol.
struct IconLabel: View {
    var title: String
    var systemImage: String
    var side: CGFloat = 24

    var body: some View {
        Label(title, systemImage: systemImage)
            .labelStyle(.iconOnly)
            .frame(width: side, height: side)
            .contentShape(Rectangle())
    }
}
