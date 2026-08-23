import SwiftUI
import ReliefCore

@MainActor
@Observable
final class ProjectDetailViewModel {

    private let projects: ProjectRepository
    let projectID: UUID
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

    /// Stages 1–5, either just computed or read back off disk. Everything the
    /// sliders touch hangs off this; `nil` means there is nothing to tune yet.
    private var checkpoint: ReliefCheckpoint?

    /// Exposed so the export sheet can build the solid from the exact
    /// field on screen rather than re-deriving one.
    private(set) var height: Plane?

    /// Owned here rather than by the view's `.task`, which is the point: a
    /// SwiftUI task is cancelled the moment its view goes away, so a conversion
    /// started that way died on the walk back to Home and began again on the
    /// walk in. These outlive the screen.
    private var task: Task<Void, Never>?
    private var refineTask: Task<Void, Never>?

    /// Whether `load()` has already decided what this project needs. A second
    /// visit re-reads the record and stops there.
    private var hasStarted = false

    // MARK: Parameters

    typealias Settings = ReliefSettings
    typealias Sliders = ReliefSliders

    /// How much of the panel is on screen. Purely a matter of disclosure: it
    /// hides sliders, it never moves them. Switching modes therefore writes
    /// nothing, commits nothing and adds no undo step — a tune made in Advanced
    /// survives a trip through Simple untouched, just out of sight.
    enum ConfigurationMode: String, CaseIterable, Identifiable {
        case simple = "Simple"
        case advanced = "Advanced"

        var id: Self { self }
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

        /// Simple keeps the two sliders that describe a physical outcome —
        /// Depth is a length in millimetres, Smoothness is rough-versus-clean
        /// and visible in the preview at a glance. Texture and Outline are
        /// solver weights: `lambda_detail` is subtle by construction, and
        /// `ordering_strength` doesn't look wrong when it's wrong, it looks
        /// broken. Neither rewards guessing, so neither is shown until asked for.
        var isAdvanced: Bool {
            switch self {
            case .depth, .smoothness: false
            case .texture, .outline:  true
            }
        }

        static func shown(in mode: ConfigurationMode) -> [Control] {
            switch mode {
            case .simple:   allCases.filter { !$0.isAdvanced }
            case .advanced: allCases
            }
        }
    }

    var settings = Settings()

    var depth: Double { settings.depth }
    var smoothness: Double { settings.smoothness }
    var texture: Double { settings.texture }
    var outline: Double { settings.outline }

    var canRefine: Bool { checkpoint != nil }

    /// What a slider move is doing right now, or `nil` when the surface on
    /// screen is the surface the sliders describe. Drives the progress bar over
    /// the preview: a re-blend at `work_res` takes long enough that without one
    /// the model looks like it flickered rather than updated.
    private(set) var refiningLabel: String?

    var isRefining: Bool { refiningLabel != nil }

    // MARK: Autosave

    /// Whether a write is in flight, just landed, or is old news.
    ///
    /// Nothing in this workspace has a Save button — the import, the checkpoint
    /// and every committed slider move are written as they happen. That is only
    /// reassuring if it is visible, so the writes report themselves rather than
    /// being silent and asking to be trusted.
    enum SaveState: Equatable {
        case idle
        case saving
        case saved

        /// One sentence, spelled once. The card, the badge and VoiceOver all
        /// read from here so none of them can start saying something the
        /// others do not.
        var note: String {
            switch self {
            case .saving: "Saving your changes"
            case .idle, .saved: "Changes saved automatically"
            }
        }
    }

    private(set) var saveState: SaveState = .idle

    /// Retires the "Saved" badge a couple of seconds after it appears. Held so
    /// a second write can cancel it rather than have its own badge cut short by
    /// the previous one's timer.
    private var saveBadgeTask: Task<Void, Never>?

    private func beginSave() {
        saveBadgeTask?.cancel()
        saveState = .saving
    }

    private func endSave() {
        saveBadgeTask?.cancel()
        saveState = .saved
        saveBadgeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.retireSaveBadge()
        }
    }

    private func retireSaveBadge() {
        guard saveState == .saved else { return }
        saveState = .idle
    }

    func value(for control: Control) -> Double { value(for: control, in: settings) }

    /// Takes the settings to read rather than always reading `settings`, so the
    /// same mapping can be pointed at a defaults struct for comparison.
    private func value(for control: Control, in settings: Settings) -> Double {
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
    func readout(for control: Control) -> String { readout(for: control, in: settings) }

    private func readout(for control: Control, in settings: Settings) -> String {
        switch control {
        case .depth:
            String(format: "%.0f mm", Sliders.reliefMm(settings.depth))
        case .smoothness, .texture, .outline:
            "\(Int((value(for: control, in: settings) * 100).rounded()))%"
        }
    }

    /// Where a slider sits when nothing has been tuned, for the mark the panel
    /// puts under the track.
    ///
    /// None of the four default to the middle of their range and one defaults
    /// to the top of it, so the thumb's position says what the value *is*
    /// without saying whether it is more or less than the pipeline's own.
    func defaultValue(for control: Control) -> Double {
        value(for: control, in: Settings())
    }

    /// Spelled exactly the way the readout box spells the live value, so the
    /// two can be compared without converting between units.
    func defaultReadout(for control: Control) -> String {
        readout(for: control, in: Settings())
    }

    /// How many of the hidden sliders are away from their default, so Simple
    /// can say so. Without it, output shaped by a value the panel isn't showing
    /// reads as the two visible sliders behaving strangely.
    var advancedEditCount: Int {
        let defaults = Settings()
        return Control.allCases.filter { control in
            control.isAdvanced && value(for: control) != value(for: control, in: defaults)
        }.count
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

    // MARK: - Loading

    /// Picks up where the project was left, which is one of three places: a
    /// checkpoint on disk, an import that has never been converted, or — for a
    /// workspace this screen has already opened once — exactly where it is.
    func load() async {
        project = await projects.project(id: projectID)
        isLoading = false

        guard !hasStarted else { return }
        hasStarted = true

        if let saved = project?.settings {
            settings = saved
            history = [saved]
            historyIndex = 0
        }

        if project?.hasCheckpoint == true {
            restore()
        } else if project?.hasSourceImage == true {
            convert()
        }
    }

    func rename(to name: String) async {
        guard var project else { return }
        project.name = name
        await projects.save(project)
        self.project = await projects.project(id: projectID)
    }

    /// The export sheet reports back through here. Exporting is a milestone,
    /// not a closing: the checkpoint stays, and so does everything that lets
    /// the project be retuned and written again.
    func markExported() async {
        await setStatus(.exported)
    }

    // MARK: - Running the pipeline

    func convert() {
        task?.cancel()
        stage = .converting(label: PipelinePhase.preprocess.label, fraction: 0)
        let config = currentConfig()
        task = Task { [weak self] in await self?.runConversion(config) }
    }

    private func runConversion(_ config: ReliefConfig) async {
        guard let data = await projects.sourceImage(id: projectID) else {
            stage = .failed("This project has no photo to convert.")
            await setStatus(.failed)
            return
        }
        await setStatus(.analyzing)

        do {
            let conversion = try await relief.convert(
                imageData: data, config: config,
                progress: { [weak self] phase, done in
                    Task { @MainActor [weak self] in
                        self?.stage = .converting(label: phase.label, fraction: done)
                    }
                })
            try Task.checkCancellation()

            adopt(conversion.checkpoint, height: conversion.height,
                  shaded: conversion.shaded)
            stage = .converting(label: PipelinePhase.mesh.label, fraction: 0.9)
            previewMesh = await relief.previewMesh(height: conversion.height,
                                                   config: config)
            try Task.checkCancellation()
            stage = .ready
            await setStatus(.ready)
            await save(conversion.checkpoint)
        } catch is CancellationError {
            stage = .idle
        } catch {
            stage = .failed(error.localizedDescription)
            await setStatus(.failed)
        }
    }

    /// Reopening a converted project. Decoding the checkpoint and re-blending
    /// it is seconds of work against the minutes stages 1–4 cost, which is the
    /// entire reason the file exists.
    private func restore() {
        task?.cancel()
        stage = .converting(label: "Opening your saved project", fraction: 0.08)
        let config = currentConfig()
        task = Task { [weak self] in await self?.runRestore(config) }
    }

    private func runRestore(_ config: ReliefConfig) async {
        guard let data = await projects.checkpoint(id: projectID),
              let saved = await relief.decodeCheckpoint(data) else {
            // The file is gone, truncated, or from a format this build cannot
            // read. Converting again is slow but it is never wrong.
            convert()
            return
        }
        guard !Task.isCancelled else { return }

        stage = .converting(label: PipelinePhase.volume.label, fraction: 0.4)
        let (surface, shaded) = await relief.reblend(saved, config: config)
        guard !Task.isCancelled else { return }
        adopt(saved, height: surface, shaded: shaded)

        stage = .converting(label: PipelinePhase.mesh.label, fraction: 0.8)
        let mesh = await relief.previewMesh(height: surface, config: config)
        guard !Task.isCancelled else { return }
        previewMesh = mesh
        stage = .ready
    }

    private func adopt(_ checkpoint: ReliefCheckpoint, height: Plane, shaded: [Float]) {
        self.checkpoint = checkpoint
        self.height = height
        preview = ReliefImage.grayImage(shaded, rows: height.rows, cols: height.cols)
        summary = "\(checkpoint.routeMode) · \(checkpoint.regionCount) regions · depth \(checkpoint.depthBackend)"
    }

    private func save(_ checkpoint: ReliefCheckpoint) async {
        beginSave()
        let data = await relief.encode(checkpoint)
        await projects.setCheckpoint(data, id: projectID)
        project = await projects.project(id: projectID)
        endSave()
    }

    /// Re-blend after a slider move. Only the Depth slider is free — it is a
    /// pure scale applied at export — but all four stay off the solver.
    func refine() {
        guard let checkpoint else { return }
        refineTask?.cancel()
        persistSettings()
        let config = currentConfig()
        refineTask = Task { [weak self] in await self?.runRefine(checkpoint, config) }
    }

    private func runRefine(_ checkpoint: ReliefCheckpoint, _ config: ReliefConfig) async {
        refiningLabel = PipelinePhase.volume.label
        let (surface, shaded) = await relief.reblend(checkpoint, config: config)
        guard !Task.isCancelled else { return }
        height = surface
        preview = ReliefImage.grayImage(shaded, rows: surface.rows, cols: surface.cols)

        refiningLabel = PipelinePhase.mesh.label
        let mesh = await relief.previewMesh(height: surface, config: config)
        // Cancelled means a newer edit is already on its way and owns the
        // label from here; clearing it would blank a bar that is still running.
        guard !Task.isCancelled else { return }
        previewMesh = mesh
        refiningLabel = nil
    }

    /// All four, including any that Simple is currently hiding: reset means
    /// back to the baseline, not back to the baseline for the half on screen.
    func resetSliders() {
        settings = Settings()
        commit()
    }

    // Writing the file used to live here. It now belongs to `ExportViewModel`,
    // behind the export sheet, which picks the format and the destination.

    // MARK: - Config

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

    // MARK: - Saving

    /// Written on every committed edit rather than on leaving the screen: there
    /// is no "leaving" to hook — the workspace is dismissed by a swipe as often
    /// as by the Back button, and the app can be killed from either.
    private func persistSettings() {
        guard project?.settings != settings else { return }
        project?.settings = settings
        beginSave()
        let snapshot = settings
        Task { [weak self] in await self?.writeSettings(snapshot) }
    }

    /// Reads the record back inside the task rather than posting the one on
    /// hand: the conversion's own status writes are in flight against the same
    /// record, and this must not carry a stale `status` over them.
    private func writeSettings(_ settings: ReliefSettings) async {
        if var latest = await projects.project(id: projectID) {
            latest.settings = settings
            await projects.save(latest)
        }
        endSave()
    }

    private func setStatus(_ status: ProjectStatus) async {
        guard var project, project.status != status else { return }
        project.status = status
        await projects.save(project)
        self.project = await projects.project(id: projectID)
    }
}
