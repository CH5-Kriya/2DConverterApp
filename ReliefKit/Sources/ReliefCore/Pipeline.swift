import Foundation

/// Stage orchestration, mirroring `relief/pipeline.py`.
///
/// Deliberately split in two:
///
///   `analyze`     stages 1-4 — expensive, dominated by neural inference
///   `synthesize`  stages 5-7 — the blend, the mesh, the files
///
/// That split is what makes the tuner usable. Every slider belongs to stage 5
/// or later, so moving one re-runs `synthesize` against a cached `Analysis`
/// instead of re-running a depth network.

/// Everything stages 1–4 produce. Expensive; cache it.
public struct Analysis: Sendable {
    public let image: Plane          // working-resolution RGB
    public let lab: Plane
    public let lightness: Plane      // Y_L, after CLAHE
    public let brightness: Plane     // Y, after the albedo divide
    public let labels: Plane
    public let regionCount: Int
    public let albedo: [Float]
    public let routing: Routing
    public let depthRaw: Plane
    public let corrected: Plane
    public let notes: [String]
}

public struct VolumeResult: Sendable {
    public let height: Plane
    public let zAi: Plane
    public let zRough: Plane
    public let zMain: Plane
    public let zDetail: Plane
    public let light: [Float]
}

/// Progress weights, from the measured shape of the pipeline.
public enum PipelinePhase: String, Sendable, CaseIterable {
    case preprocess, segment, route, albedo, depth, correct, volume, mesh, export

    public var share: Double {
        switch self {
        case .preprocess: return 0.05
        case .segment:    return 0.15
        case .route:      return 0.02
        case .albedo:     return 0.03
        case .depth:      return 0.20
        case .correct:    return 0.05
        case .volume:     return 0.25
        case .mesh:       return 0.20
        case .export:     return 0.05
        }
    }

    public var label: String {
        switch self {
        case .preprocess: return "Reading the artwork"
        case .segment:    return "Finding colour regions"
        case .route:      return "Choosing an approach"
        case .albedo:     return "Removing paint colour"
        case .depth:      return "Estimating depth"
        case .correct:    return "Cleaning up depth"
        case .volume:     return "Sculpting the surface"
        case .mesh:       return "Building the solid"
        case .export:     return "Writing the files"
        }
    }
}

public struct ReliefPipeline {
    public var config: ReliefConfig
    public var depthBackend: DepthBackend

    public init(config: ReliefConfig = ReliefConfig(),
                depthBackend: DepthBackend? = nil) {
        self.config = config
        self.depthBackend = depthBackend
            ?? ClassicalLayersBackend(layerCount: config.depth.classicalLayers)
    }

    /// Stages 1–4. The order matters: the albedo divide needs segmentation, so
    /// it runs after stage 2 rather than inside preprocess.
    public func analyze(rgb: Plane,
                        progress: ((PipelinePhase, Double) -> Void)? = nil) throws -> Analysis {
        var done = 0.0
        func step(_ phase: PipelinePhase) {
            progress?(phase, done)
            done += phase.share
        }
        var notes: [String] = []

        step(.preprocess)
        let lab = Preprocess.rgb2lab(rgb)
        var lightness = Preprocess.lightness(fromLab: lab)
        if config.preprocess.applyClahe {
            lightness = Preprocess.clahe(lightness,
                                         clipLimit: config.preprocess.claheClipLimit,
                                         tileGrid: config.preprocess.claheTileGrid)
        }

        step(.segment)
        let seg = Segment.segment(rgb: rgb, lab: lab, config: config.segment)
        notes.append("segmented into \(seg.count) regions")

        step(.route)
        let routing = Route.route(lab: lab, config: config.route)
        notes.append("routed to '\(routing.mode)' (flatness \(String(format: "%.3f", routing.score)))")

        step(.albedo)
        let brightness = config.preprocess.albedoNormalize
            ? Preprocess.albedoNormalize(lightness: lightness, labels: seg.labels,
                                         albedo: seg.albedo,
                                         floor: Float(config.preprocess.albedoFloor))
            : lightness

        step(.depth)
        let depth = try depthBackend.predict(rgb: rgb, lab: lab)
        notes.append("depth backend '\(depth.backend)': \(depth.notes)")

        step(.correct)
        let corrected = Correct.correct(depth: depth.depth, guide: lightness,
                                        config: config.correct,
                                        discrete: depth.discrete,
                                        segmentation: seg,
                                        flatArt: routing.mode == Routing.illustration)

        return Analysis(image: rgb, lab: lab, lightness: lightness,
                        brightness: brightness, labels: seg.labels,
                        regionCount: seg.count, albedo: seg.albedo,
                        routing: routing, depthRaw: depth.depth,
                        corrected: corrected, notes: notes)
    }

    /// Stage 5. Split out from `synthesize` because the four sliders re-run
    /// only the blend, not the solver.
    public func buildVolume(_ analysis: Analysis,
                            progress: ((PipelinePhase, Double) -> Void)? = nil) -> VolumeResult {
        progress?(.volume, 0.5)
        let cfg = config.volume
        let mask = Volume.foreground(depth: analysis.corrected)

        var light = config.light.vector.map { Float($0) }
        if config.light.autoEstimate {
            let estimate = Volume.estimateLight(brightness: analysis.brightness,
                                                mask: mask)
            // Below 0.05 the shading gave no clear direction and the estimate
            // is not worth trusting over the configured default.
            if estimate.confidence >= 0.05 { light = estimate.vector }
        }

        let zAi = Volume.normalize01(analysis.corrected)
        let zRough = Volume.inflate(labels: analysis.labels, foreground: mask,
                                    iters: cfg.roughSmoothIters,
                                    kernel: cfg.roughKernel)
        let zMain = (cfg.sfsEnabled && cfg.lambdaMain > 0)
            ? Volume.shapeFromShading(brightness: analysis.brightness, light: light,
                                      mask: mask, initHeight: zRough, config: cfg)
            : Plane(rows: zAi.rows, cols: zAi.cols,
                    values: [Float](repeating: 0, count: zAi.count))
        let zDetail = Volume.detail(brightness: analysis.brightness,
                                    mode: cfg.detailMode)

        let height = blend(zAi: zAi, zRough: zRough, zMain: zMain, zDetail: zDetail,
                           labels: analysis.labels, regionCount: analysis.regionCount,
                           mask: mask, config: cfg)
        return VolumeResult(height: height, zAi: zAi, zRough: zRough,
                            zMain: zMain, zDetail: zDetail, light: light)
    }

    /// Paper Eq. (8). This is the only part the four sliders touch, which is
    /// why it takes the cached Z_* layers rather than recomputing them.
    public func blend(zAi: Plane, zRough: Plane, zMain: Plane, zDetail: Plane,
                      labels: Plane, regionCount: Int, mask: [UInt8],
                      config cfg: VolumeConfig) -> Plane {
        var blended = [Float](repeating: 0, count: zAi.count)
        for i in 0..<zAi.count {
            blended[i] = Float(cfg.lambdaAi) * zAi.values[i]
                       + Float(cfg.lambdaRough) * zRough.values[i]
                       + Float(cfg.lambdaMain) * zMain.values[i]
                       + Float(cfg.lambdaDetail) * zDetail.values[i]
        }
        var plane = Volume.normalize01(
            Plane(rows: zAi.rows, cols: zAi.cols, values: blended))

        if cfg.enforceOrdering {
            plane = Volume.enforceOrdering(height: plane, zAi: zAi, labels: labels,
                                           regionCount: regionCount,
                                           strength: Float(cfg.orderingStrength))
        }
        // normalize01 runs **twice** — once before ordering and again after.
        let normed = Volume.normalize01(plane)
        return Plane(rows: zAi.rows, cols: zAi.cols,
                     values: (0..<normed.count).map {
                         normed.values[$0] * (mask[$0] != 0 ? 1 : 0) })
    }
}
