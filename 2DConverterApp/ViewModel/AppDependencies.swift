import SwiftUI

@MainActor
@Observable
final class AppDependencies {
    let projects: ProjectRepository

    // Built in the body rather than as a default argument: default argument
    // expressions evaluate outside the actor and warn under
    // SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor.
    init(projects: ProjectRepository? = nil) {
        self.projects = projects ?? InMemoryProjectRepository()
    }

    static var preview: AppDependencies {
        AppDependencies(projects: InMemoryProjectRepository())
    }
}
