import SwiftUI

@MainActor
@Observable
final class AppDependencies {
    let projects: ProjectRepository

    /// The relief pipeline. An `actor`, so its stages never land on the main
    /// thread — see `ReliefService` for why that is not automatic here.
    let relief: ReliefService

    /// Live workspaces, so a project survives a trip to Home.
    let workspaces: ProjectWorkspaceStore

    // Built in the body rather than as a default argument: default argument
    // expressions evaluate outside the actor and warn under
    // SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor.
    init(projects: ProjectRepository? = nil) {
        let repository = projects ?? FileProjectRepository()
        let service = ReliefService()
        self.projects = repository
        self.relief = service
        self.workspaces = ProjectWorkspaceStore(projects: repository, relief: service)
    }

    #if DEBUG
    static var preview: AppDependencies {
        AppDependencies(projects: InMemoryProjectRepository(seed: Project.previewSamples))
    }
    #endif
}
