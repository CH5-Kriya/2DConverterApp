import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppDependencies.self) private var dependencies

    var body: some View {
        ZStack {
            detail

            if appState.isPresentingNewProject {
                CreateProjectDialog(dependencies: dependencies)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .background(Theme.Palette.canvas)
        .preferredColorScheme(.dark)
        .animation(.snappy(duration: 0.22), value: appState.isPresentingNewProject)
    }

    /// The sidebar sits *inside* the navigation stack, as part of its root,
    /// rather than beside it.
    ///
    /// Beside it, a pushed page shared the window with the sidebar, so a page
    /// that wants the whole width — the workspace does — had to squeeze the
    /// sidebar out of the layout. That animated the sidebar away and the page
    /// wider *at the same time* as the push: a black band where the sidebar had
    /// been, and a workspace still resizing after it had arrived. The way back
    /// ran the same thing in reverse.
    ///
    /// Inside it, the stack spans the window and the sidebar is simply the
    /// leading part of its root. A pushed page is full width from its first
    /// frame and covers the sidebar; popping uncovers a root that never stopped
    /// being laid out. Nothing resizes, and which pages show the sidebar stops
    /// being a rule to maintain: pushed pages don't, the sections do.
    private var detail: some View {
        @Bindable var appState = appState

        return NavigationStack(path: $appState.detailPath) {
            HStack(spacing: 0) {
                SidebarView()
                    .frame(width: appState.isSidebarExpanded
                           ? Theme.Metrics.sidebarWidth
                           : Theme.Metrics.sidebarRailWidth)
                sectionContent
                    .id(appState.route)
                    .transition(.opacity)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
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
        }
    }
}

#if DEBUG
#Preview(traits: .landscapeLeft) {
    RootView()
        .environment(AppState())
        .environment(AppDependencies.preview)
}
#endif
