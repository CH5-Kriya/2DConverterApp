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
    private(set) var previewMesh: ReliefPreviewMesh?
    private(set) var summary: String?

    private var output: ReliefService.Output?
    /// Exposed so the export sheet can build the solid from the exact
    /// field on screen rather than re-deriving one.
    private(set) var height: Plane?
    private var task: Task<Void, Never>?

    // MARK: Parameters

    /// A named starting point for the four sliders. "Details" is the pipeline's
    /// own default tuning; "Simple" trades surface detail for a shape that
    /// prints cleanly at a coarse layer height.
    enum Preset: String, CaseIterable, Identifiable {
        case simple = "Simple"
        case details = "Details"

        var id: Self { self }

        var settings: Settings {
            switch self {
            case .simple:
                Settings(preset: .simple, depth: 0.5, smoothness: 0.8,
                         texture: 0.25, outline: 0.6)
            case .details:
                Settings(preset: .details, depth: Sliders.depthDefault,
                         smoothness: Sliders.smoothDefault,
                         texture: Sliders.textureDefault,
                         outline: Sliders.outlineDefault)
            }
        }
    }

    /// The four sliders, all normalised 0–1, plus the preset they came from.
    ///
    /// Every one of them lives in the cheap half of the pipeline, so moving one
    /// re-blends cached layers instead of re-running the solver. Grouping them
    /// into one value is what makes undo a matter of swapping a struct.
    struct Settings: Equatable {
        var preset: Preset = .details
        var depth: Double = Sliders.depthDefault      // mesh.relief_mm
        var smoothness: Double = Sliders.smoothDefault // lambda_rough vs lambda_main
        var texture: Double = Sliders.textureDefault   // lambda_detail
        var outline: Double = Sliders.outlineDefault   // ordering_strength
    }

    /// One of the four sliders. An enum rather than an index into a label
    /// array: the array and the bindings can drift apart, this can't.
    enum Control: String, CaseIterable, Identifiable {
        case depth = "Depth"
        case smoothness = "Smoothness"
        case texture = "Texture"
        case outline = "Outline"

        var id: Self { self }
        var title: String { rawValue }
    }

    var settings = Settings()

    var depth: Double { settings.depth }
    var smoothness: Double { settings.smoothness }
    var texture: Double { settings.texture }
    var outline: Double { settings.outline }

    var canRefine: Bool { output != nil }

    func value(for control: Control) -> Double {
        switch control {
        case .depth:      settings.depth
        case .smoothness: settings.smoothness
        case .texture:    settings.texture
        case .outline:    settings.outline
        }
    }

    func setValue(_ value: Double, for control: Control) {
        switch control {
        case .depth:      settings.depth = value
        case .smoothness: settings.smoothness = value
        case .texture:    settings.texture = value
        case .outline:    settings.outline = value
        }
    }

    /// Only Depth is a length. Smoothness, Texture and Outline are blend
    /// weights, so labelling them "mm" would put a fabrication number on
    /// something that isn't one.
    func readout(for control: Control) -> String {
        switch control {
        case .depth:
            String(format: "%.0f mm", Sliders.reliefMm(settings.depth))
        case .smoothness, .texture, .outline:
            "\(Int((value(for: control) * 100).rounded()))%"
        }
    }

    func select(_ preset: Preset) {
        guard preset != settings.preset else { return }
        settings = preset.settings
        commit()
    }

    init(projectID: UUID, projects: ProjectRepository, relief: ReliefService) {
        self.projectID = projectID
        self.projects = projects
        self.relief = relief
        history = [settings]
    }

    // MARK: Edit history

    private var history: [Settings] = []
    private var historyIndex = 0

    var canUndo: Bool { historyIndex > 0 }
    var canRedo: Bool { historyIndex < history.count - 1 }

    /// Records the current settings as an undoable step and re-blends.
    ///
    /// Called when an edit finishes rather than while it is in flight — a
    /// drag that sweeps a slider across its range is one edit, not sixty.
    func commit() {
        guard settings != history[historyIndex] else { return }
        history.removeSubrange((historyIndex + 1)...)
        history.append(settings)
        historyIndex = history.count - 1
        refine()
    }

    func undo() {
        guard canUndo else { return }
        historyIndex -= 1
        settings = history[historyIndex]
        refine()
    }

    func redo() {
        guard canRedo else { return }
        historyIndex += 1
        settings = history[historyIndex]
        refine()
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
            previewMesh = await service.previewMesh(height: result.height,
                                                    config: config)
            summary = "\(result.routeMode) · \(result.regionCount) regions · depth \(result.depthBackend)"
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
            let mesh = await service.previewMesh(height: newHeight, config: config)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.height = newHeight
                self?.preview = ReliefImage.grayImage(shaded, rows: newHeight.rows,
                                                      cols: newHeight.cols)
                self?.previewMesh = mesh
            }
        }
    }

    func resetSliders() {
        settings = settings.preset.settings
        commit()
    }

    // Writing the file used to live here. It now belongs to `ExportViewModel`,
    // behind the export sheet, which picks the format and the destination.

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
        config.mesh.reliefMm = Sliders.reliefMm(settings.depth)
        config.volume.lambdaRough = Sliders.lambdaRough(settings.smoothness)
        config.volume.lambdaMain = Sliders.lambdaMain(settings.smoothness)
        config.volume.lambdaDetail = Sliders.lambdaDetail(settings.texture)
        config.volume.orderingStrength = settings.outline
        config.volume.enforceOrdering = settings.outline > 0
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
