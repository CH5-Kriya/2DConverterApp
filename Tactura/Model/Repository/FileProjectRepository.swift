import Foundation

/// Projects on disk, under Application Support.
///
/// A thin main-actor face over `ProjectFileStore`, which is an `actor` so that
/// no read or write — including a twenty-megabyte checkpoint — lands on the
/// thread drawing the app.
final class FileProjectRepository: ProjectRepository {

    private let store: ProjectFileStore

    init(directory: URL? = nil) {
        store = ProjectFileStore(root: directory ?? Self.defaultDirectory)
    }

    private static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first
            ?? URL.temporaryDirectory
        return base.appendingPathComponent("Projects", isDirectory: true)
    }

    func all() async -> [Project] { await store.all() }
    func project(id: UUID) async -> Project? { await store.project(id: id) }
    func save(_ project: Project) async { await store.save(project) }
    func delete(id: UUID) async { await store.delete(id: id) }

    func sourceImage(id: UUID) async -> Data? { await store.blob(.source, id: id) }
    /// Retires the checkpoint with it. A checkpoint is stages 1–5 *of a
    /// particular image*; leaving one behind a re-crop would restore the
    /// conversion of the pixels the person just cropped away.
    func setSourceImage(_ data: Data, id: UUID) async {
        await store.setBlob(data, .source, id: id)
        await store.removeBlob(.checkpoint, id: id)
    }

    func checkpoint(id: UUID) async -> Data? { await store.blob(.checkpoint, id: id) }
    func setCheckpoint(_ data: Data, id: UUID) async {
        await store.setBlob(data, .checkpoint, id: id)
    }
}

/// The file layout, and the only thing that touches it.
///
///     Projects/<uuid>/project.json          the record
///     Projects/<uuid>/source.data           the import, as picked
///     Projects/<uuid>/checkpoint.relief     stages 1–5, encoded
///
/// One directory per project rather than one index file plus a blob store:
/// deleting a project is then a single `removeItem`, and a half-finished write
/// can only ever cost the project it belonged to.
actor ProjectFileStore {

    enum Blob {
        case source
        case checkpoint

        var fileName: String {
            switch self {
            case .source:     "source.data"
            case .checkpoint: "checkpoint.relief"
            }
        }
    }

    private let root: URL
    /// Records only — no blobs — so this stays small however many projects
    /// there are. Built on first use and maintained in step with the disk.
    private var records: [UUID: Project]?

    init(root: URL) {
        self.root = root
    }

    // MARK: Records

    func all() -> [Project] {
        index().values.sorted { $0.updatedAt > $1.updatedAt }
    }

    func project(id: UUID) -> Project? {
        index()[id]
    }

    func save(_ project: Project) {
        var updated = project
        updated.updatedAt = .now

        let folder = folder(project.id)
        try? FileManager.default.createDirectory(at: folder,
                                                 withIntermediateDirectories: true)
        // Refreshed from disk rather than trusted from the caller: the record
        // that came back from a view may predate a blob that has since landed.
        updated.hasSourceImage = exists(.source, project.id)
        updated.hasCheckpoint = exists(.checkpoint, project.id)

        if let data = try? JSONEncoder().encode(updated) {
            try? data.write(to: recordURL(project.id), options: .atomic)
        }
        var map = index()
        map[project.id] = updated
        records = map
    }

    func delete(id: UUID) {
        try? FileManager.default.removeItem(at: folder(id))
        var map = index()
        map[id] = nil
        records = map
    }

    // MARK: Blobs

    func blob(_ kind: Blob, id: UUID) -> Data? {
        try? Data(contentsOf: blobURL(kind, id), options: .mappedIfSafe)
    }

    func removeBlob(_ kind: Blob, id: UUID) {
        try? FileManager.default.removeItem(at: blobURL(kind, id))
        guard var record = index()[id] else { return }
        switch kind {
        case .source:     record.hasSourceImage = false
        case .checkpoint: record.hasCheckpoint = false
        }
        records?[id] = record
    }

    func setBlob(_ data: Data, _ kind: Blob, id: UUID) {
        let folder = folder(id)
        try? FileManager.default.createDirectory(at: folder,
                                                 withIntermediateDirectories: true)
        var url = blobURL(kind, id)
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            return
        }
        if kind == .checkpoint {
            // Regenerable, and the largest thing the app writes. Backing up
            // tens of megabytes per project that the pipeline can rebuild from
            // the import is not a good use of someone's iCloud.
            var resources = URLResourceValues()
            resources.isExcludedFromBackup = true
            try? url.setResourceValues(resources)
        }
        if var record = index()[id] {
            switch kind {
            case .source:     record.hasSourceImage = true
            case .checkpoint: record.hasCheckpoint = true
            }
            records?[id] = record
        }
    }

    // MARK: Layout

    private func index() -> [UUID: Project] {
        if let records { return records }

        var found: [UUID: Project] = [:]
        let manager = FileManager.default
        try? manager.createDirectory(at: root, withIntermediateDirectories: true)
        let entries = (try? manager.contentsOfDirectory(at: root,
                                                        includingPropertiesForKeys: nil)) ?? []
        for entry in entries {
            guard let id = UUID(uuidString: entry.lastPathComponent),
                  let data = try? Data(contentsOf: recordURL(id)),
                  var project = try? JSONDecoder().decode(Project.self, from: data)
            else { continue }
            project.hasSourceImage = exists(.source, id)
            project.hasCheckpoint = exists(.checkpoint, id)
            found[id] = project
        }
        records = found
        return found
    }

    private func exists(_ kind: Blob, _ id: UUID) -> Bool {
        FileManager.default.fileExists(atPath: blobURL(kind, id).path)
    }

    private func folder(_ id: UUID) -> URL {
        root.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    private func recordURL(_ id: UUID) -> URL {
        folder(id).appendingPathComponent("project.json")
    }

    private func blobURL(_ kind: Blob, _ id: UUID) -> URL {
        folder(id).appendingPathComponent(kind.fileName)
    }
}
