import Foundation

struct Project: Identifiable, Hashable {
    let id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date
    var status: ProjectStatus
    var sourceImageData: Data?

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        status: ProjectStatus = .draft,
        sourceImageData: Data? = nil
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.status = status
        self.sourceImageData = sourceImageData
    }
}

enum ProjectStatus: String, Hashable, CaseIterable {
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

extension Project {
    static let samples: [Project] = [
        Project(name: "Masolino — Tabitha",
                createdAt: .now.addingTimeInterval(-86_400 * 2),
                status: .exported),
        Project(name: "Studio portrait",
                createdAt: .now.addingTimeInterval(-86_400),
                status: .ready),
        Project(name: "Poster study",
                createdAt: .now.addingTimeInterval(-3_600),
                status: .draft),
    ]
}
