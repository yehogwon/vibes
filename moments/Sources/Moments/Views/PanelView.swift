import MomentsCore
import SwiftUI

/// Everything the panel shows: the list, the editor, or settings. It reports its natural height
/// so the panel can follow it.
struct PanelView: View {
    @Environment(AppState.self) private var app
    var onHeightChange: (CGFloat) -> Void

    var body: some View {
        Group {
            switch app.route {
            case .list:
                MomentListPage()
            case .editor(let moment, let isNew):
                MomentEditor(moment: moment, isNew: isNew)
                    .id(moment.id)
            case .settings:
                SettingsPage()
            }
        }
        .transition(.opacity.animation(.easeInOut(duration: 0.15)))
        .frame(width: PanelController.width)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { onHeightChange($0) }
        .frame(maxHeight: .infinity, alignment: .top)
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
                    .font(.system(size: 13, weight: .semibold))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            trailing
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }
}

/// A one-line notice, e.g. that an unreadable file was set aside.
struct Banner: View {
    var systemImage: String
    var message: String
    var dismiss: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
            Text(message)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let dismiss {
                Button("OK", action: dismiss)
                    .controlSize(.small)
            }
        }
        .font(.system(size: 11.5))
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
    }
}
