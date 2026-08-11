import SwiftUI

@MainActor
@Observable
final class ProjectDetailViewModel {

    private let projects: ProjectRepository
    private let projectID: UUID

    private(set) var project: Project?
    private(set) var isLoading = true

    init(projectID: UUID, projects: ProjectRepository) {
        self.projectID = projectID
        self.projects = projects
    }

    func load() async {
        isLoading = true
        project = await projects.project(id: projectID)
        isLoading = false
    }

    func rename(to name: String) async {
        guard var project else { return }
        project.name = name
        await projects.save(project)
        await load()
    }
}
