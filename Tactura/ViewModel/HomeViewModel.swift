import SwiftUI

@MainActor
@Observable
final class HomeViewModel {

    private let projects: ProjectRepository

    private(set) var recent: [Project] = []
    private(set) var hasLoaded = false

    /// Drives which home screen shows: the onboarding pitch or the
    /// returning-user dashboard.
    var isFirstTime: Bool { hasLoaded && recent.isEmpty }

    init(projects: ProjectRepository) {
        self.projects = projects
    }

    func load() async {
        recent = Array(await projects.all().prefix(4))
        hasLoaded = true
    }
}
