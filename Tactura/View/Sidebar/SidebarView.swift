import SwiftUI

struct SidebarView: View {
    @Environment(AppState.self) private var appState

    private var isExpanded: Bool { appState.isSidebarExpanded }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            wordmark
                .padding(.horizontal, isExpanded ? 28 : 0)
                .frame(maxWidth: .infinity, alignment: isExpanded ? .leading : .center)
                .padding(.top, 55)

            VStack(spacing: 14) {
                ForEach(AppRoute.allCases) { route in
                    SidebarRow(
                        route: route,
                        isSelected: appState.route == route,
                        isExpanded: isExpanded
                    ) {
                        appState.select(route)
                    }
                }
            }
            .padding(.horizontal, isExpanded ? 16 : 0)
            .padding(.top, 100)

            Spacer(minLength: 24)

            toggleButton
                .padding(.horizontal, isExpanded ? 16 : 0)
                .padding(.bottom, 55)
                // Opts out of the collapse animation the rest of the sidebar
                // runs. Its label is the widest thing in the column, so
                // animating it drags a stretching "Hide Menu" across the whole
                // transition; snapping puts it out of the way at once.
                .animation(nil, value: isExpanded)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Theme.Palette.sidebar)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Theme.Palette.separator)
                .frame(width: 1)
        }
    }

    private var wordmark: some View {
        HStack(spacing: 14) {
            AppMarkView()
                .frame(width: 32, height: 32)
            if isExpanded {
                Text("Tactura")
                    .font(Theme.Typography.wordmark)
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .fixedSize()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Tactura")
    }

    private var toggleButton: some View {
        Button {
            appState.toggleSidebar()
        } label: {
            SidebarItemLabel(
                systemImage: "sidebar.leading",
                title: "Hide Menu",
                isExpanded: isExpanded,
                isSelected: false
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isExpanded ? "Hide menu" : "Show menu")
    }
}

/// The app icon, reused as the in-app mark.
///
/// Clipped to the squircle ratio iOS uses for icons. The artwork already
/// carries rounded corners, but it ships without an alpha channel, so the
/// pixels outside them are opaque filler that would otherwise read as a pale
/// square against the dark sidebar.
struct AppMarkView: View {
    var body: some View {
        GeometryReader { proxy in
            Image("AppMark")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: proxy.size.width * 0.2237,
                                            style: .continuous))
        }
    }
}

#Preview {
    HStack(spacing: 0) {
        SidebarView()
            .frame(width: Theme.Metrics.sidebarWidth)
        SidebarView()
            .frame(width: Theme.Metrics.sidebarRailWidth)
    }
    .environment(AppState())
    .preferredColorScheme(.dark)
}
