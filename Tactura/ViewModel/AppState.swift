import SwiftUI

enum AppRoute: String, CaseIterable, Identifiable, Hashable {
    case home
    case myScans
    case tutorials

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home:      "Home"
        case .myScans:   "My Scans"
        case .tutorials: "Tutorials"
        }
    }

    var icon: String {
        switch self {
        case .home:      "house"
        case .myScans:   "bookmark"
        case .tutorials: "lightbulb"
        }
    }

    var selectedIcon: String {
        switch self {
        case .home:      "house.fill"
        case .myScans:   "bookmark.fill"
        case .tutorials: "lightbulb.fill"
        }
    }
}

/// Pages pushed on top of a sidebar route.
enum AppDestination: Hashable {
    /// Between importing a photograph and converting it. Cropping earns its
    /// place here because the pipeline resamples to `work_res` on the long
    /// edge — pixels spent on a frame or a wall are detail the relief never
    /// receives, and no later step can buy them back.
    case crop(UUID)
    case project(UUID)
}

@MainActor
@Observable
final class AppState {
    var route: AppRoute = .home
    var detailPath: [AppDestination] = []

    /// Collapsed does not mean gone: the rail stays as icons only. A pushed
    /// page hides the sidebar outright, but that is `RootView`'s layout rather
    /// than this flag: the two are independent, so coming back out of the
    /// workspace restores whatever width the person had chosen.
    var isSidebarExpanded = true

    var isPresentingNewProject = false

    /// Switching sidebar sections unwinds whatever was pushed on top of the
    /// previous one, so going back to it does not resume a stale stack.
    func select(_ route: AppRoute) {
        detailPath.removeAll()
        self.route = route
    }

    func open(_ destination: AppDestination, in route: AppRoute) {
        if self.route != route {
            self.route = route
            detailPath = [destination]
        } else {
            detailPath.append(destination)
        }
    }

    func toggleSidebar() {
        isSidebarExpanded.toggle()
    }
}
