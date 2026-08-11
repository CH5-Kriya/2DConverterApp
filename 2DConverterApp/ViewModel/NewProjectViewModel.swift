import PhotosUI
import SwiftUI

@MainActor
@Observable
final class NewProjectViewModel {

    private let projects: ProjectRepository

    var isPresentingPicker = false
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
            let project = Project(
                name: Self.defaultName(),
                status: .draft,
                sourceImageData: data
            )
            await projects.save(project)
            createdProject = project
        } catch {
            errorMessage = error.localizedDescription
        }
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
