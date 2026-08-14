import SwiftUI
import ReliefCore

@MainActor
@Observable
final class ProjectDetailViewModel {

    private let projects: ProjectRepository
    private let projectID: UUID
    let relief: ReliefService

    private(set) var project: Project?
    private(set) var isLoading = true

    // MARK: Conversion

    /// Mirrors the flow the pipeline is built around: import → preview →
    /// optional refinement → export. The preview appears on its own; refining
    /// is a choice, not a step the user has to complete.
    enum Stage: Equatable {
        case idle
        case converting(label: String, fraction: Double)
        case ready
        case failed(String)
    }

    private(set) var stage: Stage = .idle
    private(set) var preview: CGImage?
    private(set) var summary: String?

    private var output: ReliefService.Output?
    /// Exposed so the export sheet can build the solid from the exact
    /// field on screen rather than re-deriving one.
    private(set) var height: Plane?
    private var task: Task<Void, Never>?

    /// The four refinement sliders, all normalised 0–1.
    ///
    /// Every one of them lives in the cheap half of the pipeline, so moving one
    /// re-blends cached layers instead of re-running the solver.
    var depth: Double = Sliders.depthDefault      // mesh.relief_mm
    var smoothness: Double = Sliders.smoothDefault // lambda_rough vs lambda_main
    var texture: Double = Sliders.textureDefault   // lambda_detail
    var outline: Double = Sliders.outlineDefault   // ordering_strength

    var canRefine: Bool { output != nil }

    init(projectID: UUID, projects: ProjectRepository, relief: ReliefService) {
        self.projectID = projectID
        self.projects = projects
        self.relief = relief
    }

    func load() async {
        isLoading = true
        project = await projects.project(id: projectID)
        isLoading = false
        if project?.sourceImageData != nil && stage == .idle {
            await convert()
        }
    }

    func rename(to name: String) async {
        guard var project else { return }
        project.name = name
        await projects.save(project)
        await load()
    }

    // MARK: - Running the pipeline

    func convert() async {
        guard let data = project?.sourceImageData else { return }
        task?.cancel()

        await setStatus(.analyzing)
        stage = .converting(label: PipelinePhase.preprocess.label, fraction: 0)

        let config = currentConfig()
        let service = relief

        do {
            let result = try await service.convert(
                imageData: data, config: config,
                progress: { [weak self] phase, done in
                    Task { @MainActor in
                        self?.stage = .converting(label: phase.label, fraction: done)
                    }
                })
            output = result
            height = result.height
            preview = ReliefImage.grayImage(result.previewShaded,
                                            rows: result.previewRows,
                                            cols: result.previewCols)
            summary = "\(result.routeMode) · \(result.regionCount) regions"
            stage = .ready
            await setStatus(.ready)
        } catch is CancellationError {
            stage = .idle
        } catch {
            stage = .failed(error.localizedDescription)
            await setStatus(.failed)
        }
    }

    /// Re-blend after a slider move. Only the Depth slider is free — it is a
    /// pure scale applied at export — but all four stay off the solver.
    func refine() {
        guard let output else { return }
        task?.cancel()
        let config = currentConfig()
        let service = relief
        task = Task { [weak self] in
            let (newHeight, shaded) = await service.reblend(output, config: config)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.height = newHeight
                self?.preview = ReliefImage.grayImage(shaded, rows: newHeight.rows,
                                                      cols: newHeight.cols)
            }
        }
    }

    func resetSliders() {
        depth = Sliders.depthDefault
        smoothness = Sliders.smoothDefault
        texture = Sliders.textureDefault
        outline = Sliders.outlineDefault
        refine()
    }

    func exportSTL() async -> URL? {
        guard let height else { return nil }
        let (data, mesh) = await relief.exportSTL(height: height, config: currentConfig())
        let name = (project?.name ?? "relief").replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name).stl")
        do {
            try data.write(to: url)
            summary = String(format: "%.0f x %.0f mm · %d faces · %@",
                             mesh.widthMm, mesh.heightMm, mesh.faceCount,
                             mesh.isWatertight ? "watertight" : "NOT watertight")
            await setStatus(.exported)
            return url
        } catch {
            stage = .failed(error.localizedDescription)
            return nil
        }
    }

    // MARK: - Config

    /// Slider positions mapped onto the pipeline's own parameters.
    enum Sliders {
        static let depthDefault = 0.72      // ~30 mm, the reference export
        static let smoothDefault = 0.5
        static let textureDefault = 0.8     // lambda_detail 0.04 of a 0.05 cap
        static let outlineDefault = 1.0

        static func reliefMm(_ t: Double) -> Double { 4 + t * 36 }        // 4–40 mm
        static func lambdaRough(_ t: Double) -> Double { t * 0.7 }        // 0–0.7
        static func lambdaMain(_ t: Double) -> Double { 0.7 - t * 0.5 }   // 0.7–0.2
        static func lambdaDetail(_ t: Double) -> Double { t * 0.05 }      // capped at 0.05
    }

    func currentConfig() -> ReliefConfig {
        var config = ReliefConfig()
        config.mesh.reliefMm = Sliders.reliefMm(depth)
        config.volume.lambdaRough = Sliders.lambdaRough(smoothness)
        config.volume.lambdaMain = Sliders.lambdaMain(smoothness)
        config.volume.lambdaDetail = Sliders.lambdaDetail(texture)
        config.volume.orderingStrength = outline
        config.volume.enforceOrdering = outline > 0
        config.export.intermediates = false
        return config
    }

    private func setStatus(_ status: ProjectStatus) async {
        guard var project else { return }
        project.status = status
        await projects.save(project)
        self.project = project
    }
}
