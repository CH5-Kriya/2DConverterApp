import Foundation
import ReliefCore

/// Runs the relief pipeline off the main thread.
///
/// This is an `actor` deliberately. The target builds with
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so an unannotated type here
/// would be main-actor isolated and every stage — including a 300-sweep solver
/// — would run on the UI thread and freeze the app.
actor ReliefService {

    /// A finished conversion: the checkpoint the tuner goes on working from,
    /// and the first surface blended out of it.
    struct Conversion {
        let checkpoint: ReliefCheckpoint
        let height: Plane
        let shaded: [Float]
    }

    enum Failure: LocalizedError {
        case badImage
        case cancelled

        var errorDescription: String? {
            switch self {
            case .badImage: return "That file could not be read as an image."
            case .cancelled: return "Conversion was cancelled."
            }
        }
    }

    /// Stages 1–5. The expensive half; its result is checkpointed so the
    /// sliders — and every later visit to the project — re-run only the blend.
    func convert(imageData: Data,
                 config: ReliefConfig,
                 progress: @Sendable @escaping (PipelinePhase, Double) -> Void)
        async throws -> Conversion {

        guard let rgb = ReliefImage.load(data: imageData,
                                         maxEdge: config.preprocess.workRes) else {
            throw Failure.badImage
        }

        // Real model where it is bundled; the dependency-free heuristic
        // otherwise, so a missing or unloadable model degrades output quality
        // instead of blocking the run — the same policy the reference has.
        let backend: DepthBackend = CoreMLDepthBackend.bundled()
            ?? ClassicalLayersBackend(layerCount: config.depth.classicalLayers)

        let pipeline = ReliefPipeline(config: config, depthBackend: backend)
        let analysis = try pipeline.analyze(rgb: rgb, progress: progress)

        // Depth is finished; at fp16 those weights are the largest single
        // allocation in the app and the mesh stage is next.
        (backend as? CoreMLDepthBackend)?.unload()
        try Task.checkCancellation()

        let volume = pipeline.buildVolume(analysis, progress: progress)
        try Task.checkCancellation()

        let checkpoint = ReliefCheckpoint(
            labels: analysis.labels,
            regionCount: analysis.regionCount,
            mask: Volume.foreground(depth: analysis.corrected),
            zAi: volume.zAi, zRough: volume.zRough,
            zMain: volume.zMain, zDetail: volume.zDetail,
            routeMode: analysis.routing.mode,
            depthBackend: pipeline.depthBackend.name)

        // `analysis` goes out of scope here, and with it the working image, its
        // Lab, the lightness and brightness fields and the raw depth — some
        // eighty megabytes at `work_res` that nothing downstream of the blend
        // ever reads again.
        return Conversion(checkpoint: checkpoint,
                          height: volume.height,
                          shaded: ReliefImage.shade(volume.height))
    }

    /// Re-blend with new slider values. Cheap: the four Z_* layers are already
    /// computed, so this is a weighted sum plus the ordering pass.
    func reblend(_ checkpoint: ReliefCheckpoint, config: ReliefConfig) -> (Plane, [Float]) {
        let pipeline = ReliefPipeline(config: config)
        let height = pipeline.blend(zAi: checkpoint.zAi,
                                    zRough: checkpoint.zRough,
                                    zMain: checkpoint.zMain,
                                    zDetail: checkpoint.zDetail,
                                    labels: checkpoint.labels,
                                    regionCount: checkpoint.regionCount,
                                    mask: checkpoint.mask,
                                    config: config.volume)
        return (height, ReliefImage.shade(height))
    }

    /// Both directions of the checkpoint file, here rather than at the call
    /// site so that quantising twenty megabytes never happens on the main
    /// thread — which is the whole reason this type is an actor.
    func encode(_ checkpoint: ReliefCheckpoint) -> Data {
        checkpoint.encoded()
    }

    func decodeCheckpoint(_ data: Data) -> ReliefCheckpoint? {
        ReliefCheckpoint.decode(data)
    }

    /// The height field closed into a solid for the on-screen 3D preview.
    ///
    /// Separate from `exportSTL` on purpose: the export mesh is built at the
    /// print grid and decimated to a face budget a slicer wants, which is far
    /// more work than a view that rebuilds on every slider release can afford.
    func previewMesh(height: Plane, config: ReliefConfig) -> ReliefPreviewMesh {
        ReliefPreviewMeshBuilder.build(height: height, config: config.mesh)
    }

    /// Stages 6–7, run on export rather than on every slider move.
    func exportSTL(height: Plane, config: ReliefConfig) -> (Data, SolidMesh) {
        let mesh = Mesh.build(height: height, config: config.mesh)
        return (Export.binarySTL(mesh), mesh)
    }

    /// Stages 6–7 for whichever deliverable was asked for.
    ///
    /// The mesh is built either way: even the height map reports its printed
    /// dimensions and watertightness, and those come from the solid rather than
    /// from the field it was raised out of.
    func exportPayload(height: Plane,
                       config: ReliefConfig,
                       format: ExportFormat) -> (Data, SolidMesh) {
        let mesh = Mesh.build(height: height, config: config.mesh)
        switch format {
        case .stl:
            return (Export.binarySTL(mesh), mesh)
        case .heightMap:
            let samples = Export.heightMap16(height)
            let data = ReliefImage.gray16PNG(samples,
                                             rows: height.rows,
                                             cols: height.cols) ?? Data()
            return (data, mesh)
        }
    }
}
