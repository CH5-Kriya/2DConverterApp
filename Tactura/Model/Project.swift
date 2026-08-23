import Foundation

/// A project's record: what the lists need to draw it and what the workspace
/// needs to pick it back up. The bulky parts — the full-resolution import and
/// the pipeline checkpoint — live beside it in the store rather than in it, so
/// listing thirty projects does not mean holding thirty photographs.
nonisolated struct Project: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date
    var status: ProjectStatus

    /// Where the sliders were left. Saved with every edit, which is what makes
    /// reopening a project resume the tuning rather than restart it.
    var settings: ReliefSettings

    /// A small JPEG of the artwork, for the rows and cards. The full import is
    /// several megabytes; a list of them is not something to decode to show
    /// squares 76 points wide.
    var thumbnail: Data?

    /// What the store actually holds for this project.
    ///
    /// Not persisted. The repository fills these in from the files that are
    /// there, so a record can never claim an image or a checkpoint the store
    /// lost — the failure that would otherwise send the workspace to restore
    /// something that is not on disk.
    var hasSourceImage = false
    var hasCheckpoint = false

    private enum CodingKeys: String, CodingKey {
        case id, name, createdAt, updatedAt, status, settings, thumbnail
    }

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        status: ProjectStatus = .draft,
        settings: ReliefSettings = ReliefSettings(),
        thumbnail: Data? = nil
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.status = status
        self.settings = settings
        self.thumbnail = thumbnail
    }
}

/// How far a project has been carried.
///
/// Everything from the import onward is already saved, so these are not save
/// states — they are the answer to "what is waiting for me here", which is why
/// `exported` is a milestone rather than an ending: an exported project can
/// still be retuned and written again.
nonisolated enum ProjectStatus: String, Hashable, Codable, CaseIterable {
    case draft
    case analyzing
    case ready
    case exported
    case failed

    var label: String {
        switch self {
        case .draft:     "Draft"
        case .analyzing: "Analyzing"
        case .ready:     "Ready"
        case .exported:  "Exported"
        case .failed:    "Failed"
        }
    }
}
