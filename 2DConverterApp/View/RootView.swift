import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppDependencies.self) private var dependencies

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                SidebarView()
                    .frame(width: appState.isSidebarExpanded
                           ? Theme.Metrics.sidebarWidth
                           : Theme.Metrics.sidebarRailWidth)
                detail
            }

            if appState.isPresentingNewProject {
                CreateProjectDialog(dependencies: dependencies)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .background(Theme.Palette.canvas)
        .preferredColorScheme(.dark)
        .animation(Theme.Metrics.sidebarAnimation, value: appState.isSidebarExpanded)
        .animation(.snappy(duration: 0.22), value: appState.isPresentingNewProject)
    }

    private var detail: some View {
        @Bindable var appState = appState

        return NavigationStack(path: $appState.detailPath) {
            sectionContent
                .id(appState.route)
                .transition(.opacity)
                .background(Theme.Palette.canvas)
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: AppDestination.self) { destination in
                    switch destination {
                    case .crop(let id):
                        CropView(projectID: id, dependencies: dependencies)
                            .background(Theme.Palette.canvas)
                    case .project(let id):
                        ProjectDetailView(projectID: id, dependencies: dependencies)
                            .background(Theme.Palette.canvas)
                    }
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.2), value: appState.route)
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch appState.route {
        case .home:      HomeView(dependencies: dependencies)
        case .myScans:   MyScansView(dependencies: dependencies)
        case .tutorials: TutorialsView()
        case .settings:  SettingsView()
        }
    }
}

#Preview(traits: .landscapeLeft) {
    RootView()
        .environment(AppState())
        .environment(AppDependencies.preview)
}
