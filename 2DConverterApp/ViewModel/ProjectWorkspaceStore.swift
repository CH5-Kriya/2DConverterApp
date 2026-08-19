import SwiftUI

/// Keeps a project's workspace alive across navigation.
///
/// `ProjectDetailView` is rebuilt from nothing every time it is pushed, so a
/// view model created in its initialiser was a new one on every visit — and a
/// new one has no checkpoint, no preview and no running conversion, which is
/// why walking to Home and back used to start the pipeline over. Handing back
/// the same instance is what makes leaving the screen a navigation rather than
/// a discard.
@MainActor
@Observable
final class ProjectWorkspaceStore {

    private let projects: ProjectRepository
    private let relief: ReliefService

    private var workspaces: [UUID: ProjectDetailViewModel] = [:]
    /// Most recently opened last.
    private var order: [UUID] = []

    /// A workspace holds the checkpoint it is tuning — some fifty megabytes of
    /// height fields at `work_res`. Two is enough to make going back and forth
    /// between a pair of projects free; past that the checkpoint file is the
    /// cache, and reopening costs a re-blend rather than a conversion.
    private let limit = 2

    init(projects: ProjectRepository, relief: ReliefService) {
        self.projects = projects
        self.relief = relief
    }

    func workspace(for id: UUID) -> ProjectDetailViewModel {
        order.removeAll { $0 == id }
        order.append(id)

        if let existing = workspaces[id] { return existing }

        let workspace = ProjectDetailViewModel(projectID: id, projects: projects,
                                               relief: relief)
        workspaces[id] = workspace
        evictIfNeeded()
        return workspace
    }

    /// Called when a project is deleted: whatever the workspace was holding is
    /// about to describe something that no longer exists.
    func discard(_ id: UUID) {
        workspaces[id] = nil
        order.removeAll { $0 == id }
    }

    /// Never the project just asked for — that one is at the end of `order` —
    /// and never one still converting, which is the run this whole type exists
    /// to protect.
    private func evictIfNeeded() {
        while workspaces.count > limit,
              let stale = order.first(where: { id in
                  guard let workspace = workspaces[id] else { return false }
                  if case .converting = workspace.stage { return false }
                  return true
              }) {
            discard(stale)
        }
    }
}
