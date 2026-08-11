import SwiftUI

@MainActor
@Observable
final class MyScansViewModel {

    private let projects: ProjectRepository

    private(set) var items: [Project] = []
    private(set) var isLoading = false

    init(projects: ProjectRepository) {
        self.projects = projects
    }

    var isEmpty: Bool { !isLoading && items.isEmpty }

    func load() async {
        isLoading = true
        items = await projects.all()
        isLoading = false
    }

    func delete(_ project: Project) async {
        await projects.delete(id: project.id)
        await load()
    }
}
