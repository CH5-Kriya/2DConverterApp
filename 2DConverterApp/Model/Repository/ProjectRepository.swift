import Foundation

/// Records and blobs are fetched separately on purpose.
///
/// A `Project` is small enough that listing every one of them is free; the
/// import behind it is megabytes and the checkpoint beside it is tens of them.
/// Keeping the three apart is what lets My Scans draw thirty projects without
/// loading a single photograph.
protocol ProjectRepository {
    func all() async -> [Project]
    func project(id: UUID) async -> Project?
    func save(_ project: Project) async
    func delete(id: UUID) async

    /// The full-resolution import, as it came out of the picker or the cropper.
    func sourceImage(id: UUID) async -> Data?
    func setSourceImage(_ data: Data, id: UUID) async

    /// An encoded `ReliefCheckpoint` — stages 1–5, so reopening a project does
    /// not mean running a depth network over it again.
    func checkpoint(id: UUID) async -> Data?
    func setCheckpoint(_ data: Data, id: UUID) async
}

/// Non-persistent — everything is gone on relaunch. For previews and tests;
/// the app runs on `FileProjectRepository`.
@Observable
final class InMemoryProjectRepository: ProjectRepository {

    private var storage: [UUID: Project]
    private var sources: [UUID: Data] = [:]
    private var checkpoints: [UUID: Data] = [:]

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
        updated.hasSourceImage = sources[project.id] != nil
        updated.hasCheckpoint = checkpoints[project.id] != nil
        storage[project.id] = updated
    }

    func delete(id: UUID) async {
        storage[id] = nil
        sources[id] = nil
        checkpoints[id] = nil
    }

    func sourceImage(id: UUID) async -> Data? { sources[id] }

    func setSourceImage(_ data: Data, id: UUID) async {
        sources[id] = data
        checkpoints[id] = nil
        storage[id]?.hasSourceImage = true
        storage[id]?.hasCheckpoint = false
    }

    func checkpoint(id: UUID) async -> Data? { checkpoints[id] }

    func setCheckpoint(_ data: Data, id: UUID) async {
        checkpoints[id] = data
        storage[id]?.hasCheckpoint = true
    }
}
