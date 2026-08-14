import Foundation

protocol ProjectRepository {
    func all() async -> [Project]
    func project(id: UUID) async -> Project?
    func save(_ project: Project) async
    func delete(id: UUID) async
}

/// Non-persistent — everything is gone on relaunch. Swap for a SwiftData
/// implementation before shipping.
@Observable
final class InMemoryProjectRepository: ProjectRepository {

    private var storage: [UUID: Project]

    /// Empty by default: a fresh install opens on the first-run state, not on
    /// someone else's projects. Seeding is for previews and tests only.
    init(seed: [Project] = []) {
        storage = Dictionary(uniqueKeysWithValues: seed.map { ($0.id, $0) })
    }

    func all() async -> [Project] {
        storage.values.sorted { $0.updatedAt > $1.updatedAt }
    }

    func project(id: UUID) async -> Project? {
        storage[id]
    }

    func save(_ project: Project) async {
        var updated = project
        updated.updatedAt = .now
        storage[project.id] = updated
    }

    func delete(id: UUID) async {
        storage[id] = nil
    }
}
