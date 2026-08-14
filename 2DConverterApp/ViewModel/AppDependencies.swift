import SwiftUI

@MainActor
@Observable
final class AppDependencies {
    let projects: ProjectRepository

    /// The relief pipeline. An `actor`, so its stages never land on the main
    /// thread — see `ReliefService` for why that is not automatic here.
    let relief: ReliefService

    // Built in the body rather than as a default argument: default argument
    // expressions evaluate outside the actor and warn under
    // SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor.
    init(projects: ProjectRepository? = nil) {
        self.projects = projects ?? InMemoryProjectRepository()
        self.relief = ReliefService()
    }

    static var preview: AppDependencies {
        AppDependencies(projects: InMemoryProjectRepository())
    }
}
