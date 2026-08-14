import SwiftUI

@MainActor
@Observable
final class MyScansViewModel {

    private let projects: ProjectRepository

    private(set) var items: [Project] = []
    private(set) var isLoading = false

    /// Live search text. Filtering lives here rather than in the view so the
    /// view never has to know that a search is a predicate over the model.
    var query: String = ""

    init(projects: ProjectRepository) {
        self.projects = projects
    }

    /// `localizedStandardContains` rather than `contains`: it is
    /// case- and diacritic-insensitive, which is what a person means by
    /// "search" and what `contains` conspicuously is not.
    var visible: [Project] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return items }
        return items.filter { $0.name.localizedStandardContains(trimmed) }
    }

    /// Nothing at all, as opposed to nothing *matching* — the two want
    /// different words on screen.
    var hasNoProjects: Bool { !isLoading && items.isEmpty }
    var hasNoMatches: Bool { !isLoading && !items.isEmpty && visible.isEmpty }

    var countLabel: String {
        let n = items.count
        return "\(n) project\(n == 1 ? "" : "s")"
    }

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
