#if DEBUG
import Foundation

/// Fixtures for SwiftUI previews.
///
/// Behind `#if DEBUG` so it cannot reach a shipping build: this is the data
/// that used to seed `InMemoryProjectRepository`, which meant every launch —
/// including a fresh install — opened on three projects the user never made.
extension Project {
    static let previewSamples: [Project] = [
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
#endif
