import SwiftUI

struct SidebarView: View {
    @Environment(AppState.self) private var appState

    private var isExpanded: Bool { appState.isSidebarExpanded }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            wordmark
                .padding(.horizontal, isExpanded ? 28 : 0)
                .frame(maxWidth: .infinity, alignment: isExpanded ? .leading : .center)
                .padding(.top, 44)

            VStack(spacing: 6) {
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
            .padding(.top, 56)

            Spacer(minLength: 24)

            toggleButton
                .padding(.horizontal, isExpanded ? 16 : 0)
                .padding(.bottom, 32)
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
                .frame(width: 40, height: 40)
            if isExpanded {
                Text("Kriya App")
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

struct AppMarkView: View {
    var body: some View {
        Image(systemName: "cube.fill")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .foregroundStyle(
                LinearGradient(
                    colors: [.white, Color(hex: 0x8E8E8E)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
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
