import SwiftUI
import UIKit

@MainActor
@Observable
final class CropViewModel {

    private let projects: ProjectRepository
    private let workspaces: ProjectWorkspaceStore
    private let projectID: UUID

    private(set) var project: Project?
    private(set) var image: UIImage?
    private(set) var isLoading = true
    private(set) var errorMessage: String?

    var crop: CropRect = .full
    var aspect: CropAspect = .free {
        didSet { applyAspect() }
    }

    init(projectID: UUID, dependencies: AppDependencies) {
        self.projectID = projectID
        self.projects = dependencies.projects
        self.workspaces = dependencies.workspaces
    }

    // MARK: Derived

    var pixelSize: CGSize {
        guard let image else { return .zero }
        return CGSize(width: image.size.width * image.scale,
                      height: image.size.height * image.scale)
    }

    var originalAspect: Double {
        let size = pixelSize
        guard size.height > 0 else { return 1 }
        return size.width / size.height
    }

    var cropPixels: CGRect { crop.pixels(in: pixelSize) }

    /// The chosen ratio, restated in the crop rectangle's own space.
    ///
    /// `CropAspect` states ratios in image terms: 1 : 1 means a square number
    /// of *pixels*. `CropRect` is fractions of the source, and that space is
    /// square whatever shape the source is — so on a 4:3 photograph a rectangle
    /// with equal fractions is 4:3, not square, and the source's own aspect has
    /// to be divided back out before the number means anything here.
    ///
    /// Everything that locks a ratio reads it from here. It used to be worked
    /// out twice — converted in `applyAspect`, not converted in the overlay's
    /// corner drag — which is why picking a preset looked right until the
    /// moment you touched a corner, and then came out at `ratio × original`.
    var normalisedAspect: Double? {
        guard let ratio = aspect.ratio(originalAspect: originalAspect) else { return nil }
        return ratio / originalAspect
    }

    /// Shown in the Width/Height fields. Source pixels, not points — this is
    /// the number that decides how much detail survives the resample to
    /// `work_res`, so it is the one worth putting in front of a person.
    var widthText: String { "\(Int(cropPixels.width))" }
    var heightText: String { "\(Int(cropPixels.height))" }

    var isUntouched: Bool { crop == .full && aspect == .free }

    // MARK: Loading

    func load() async {
        isLoading = true
        project = await projects.project(id: projectID)
        if let data = await projects.sourceImage(id: projectID),
           let decoded = UIImage(data: data) {
            image = decoded
        } else {
            errorMessage = "That image could not be read."
        }
        isLoading = false
    }

    // MARK: Editing

    func reset() {
        aspect = .free
        crop = .full
    }

    func setWidth(_ text: String) {
        guard let value = Double(text), pixelSize.width > 0 else { return }
        var next = crop
        next.width = value / pixelSize.width
        if let target = normalisedAspect {
            next.height = next.width / target
        }
        crop = next.clamped(to: normalisedAspect)
    }

    func setHeight(_ text: String) {
        guard let value = Double(text), pixelSize.height > 0 else { return }
        var next = crop
        next.height = value / pixelSize.height
        if let target = normalisedAspect {
            next.width = next.height * target
        }
        crop = next.clamped(to: normalisedAspect)
    }

    /// Re-shape the current rectangle to the chosen ratio, keeping its centre.
    private func applyAspect() {
        guard let target = normalisedAspect else { return }
        let centreX = crop.x + crop.width / 2
        let centreY = crop.y + crop.height / 2

        // Only ever shrinks the side that is too long, so a rectangle that was
        // inside the image stays inside it.
        var next = crop
        if next.width / next.height > target {
            next.width = next.height * target
        } else {
            next.height = next.width / target
        }
        next.x = centreX - next.width / 2
        next.y = centreY - next.height / 2
        crop = next.clamped(to: target)
    }

    // MARK: Committing

    /// Writes the cropped image back onto the project and hands back the id, so
    /// the caller can move on to the conversion.
    ///
    /// Cropping *before* conversion rather than after is the whole point: the
    /// pipeline resamples to `work_res` on the long edge, so every pixel spent
    /// on a frame or a wall is detail the relief never gets.
    func commit() async -> UUID? {
        guard var project, let image else { return nil }

        if !isUntouched, let cropped = Self.crop(image, to: cropPixels),
           let data = cropped.jpegData(compressionQuality: 0.95) {
            await projects.setSourceImage(data, id: project.id)
            // The store has retired the checkpoint; this retires the copy a
            // workspace opened earlier in this session is still holding.
            workspaces.discard(project.id)
            // The lists show the artwork, and the artwork is now what is inside
            // the frame — a thumbnail of the uncropped import would advertise
            // exactly the pixels the person just decided to throw away.
            project.thumbnail = ProjectThumbnail.make(from: data)
            await projects.save(project)
        }
        return project.id
    }

    private static func crop(_ image: UIImage, to rect: CGRect) -> UIImage? {
        guard let cg = image.cgImage else { return nil }
        let bounded = rect.intersection(CGRect(x: 0, y: 0,
                                               width: cg.width, height: cg.height))
        guard !bounded.isEmpty, let cut = cg.cropping(to: bounded) else { return nil }
        // Scale 1 and up orientation: the pixels have already been rotated into
        // place by the crop, so carrying the original's orientation would apply
        // the rotation twice.
        return UIImage(cgImage: cut, scale: 1, orientation: .up)
    }
}
