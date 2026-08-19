import PhotosUI
import SwiftUI

@MainActor
@Observable
final class NewProjectViewModel {

    private let projects: ProjectRepository

    var isPresentingPicker = false
    var isPresentingCamera = false
    var pickedItem: PhotosPickerItem?
    var isImporting = false
    var errorMessage: String?

    var hasError: Bool {
        get { errorMessage != nil }
        set { if !newValue { errorMessage = nil } }
    }

    private(set) var createdProject: Project?

    init(projects: ProjectRepository) {
        self.projects = projects
    }

    /// The import is the first checkpoint. By the time this returns, the photo
    /// and a project to hang it on are on disk — closing the app on the crop
    /// screen loses the crop, never the artwork.
    func importPick() async {
        guard let pickedItem else { return }
        isImporting = true
        defer {
            isImporting = false
            self.pickedItem = nil
        }

        do {
            guard let data = try await pickedItem.loadTransferable(type: Data.self) else {
                errorMessage = "That image could not be read."
                return
            }
            await create(from: data)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// A scan, once the camera has handed back a photograph.
    ///
    /// The same checkpoint as a gallery import, and deliberately the same code
    /// underneath it: from here on the two are indistinguishable, so the crop
    /// step and everything after it only ever has one kind of project to open.
    func importCaptured(_ data: Data) async {
        isImporting = true
        defer { isImporting = false }
        await create(from: data)
    }

    private func create(from data: Data) async {
        let project = Project(
            name: Self.defaultName(),
            status: .draft,
            thumbnail: ProjectThumbnail.make(from: data)
        )
        await projects.save(project)
        await projects.setSourceImage(data, id: project.id)
        createdProject = await projects.project(id: project.id)
    }

    func clearCreatedProject() {
        createdProject = nil
    }

    private static func defaultName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM, HH:mm"
        return "Scan \(formatter.string(from: .now))"
    }
}
