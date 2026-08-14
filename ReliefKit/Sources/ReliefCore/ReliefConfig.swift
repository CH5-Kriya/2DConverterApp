import Foundation

/// Every tunable in the pipeline, mirroring `src/relief/config.py` field for
/// field.
///
/// The Python side is the specification, so the defaults here are not
/// independent choices — they are copies, and a difference is a bug. The golden
/// fixtures dump the exact config they were produced with, and
/// `relief-verify` decodes that into these types, which means a drift shows up
/// as a failing comparison rather than as a mystery downstream.
///
/// Keys are snake_case on the wire because that is what Python emits; decoding
/// uses `.convertFromSnakeCase` rather than hand-written `CodingKeys`.
///
/// Every struct below writes `init(from:)` by hand. That is not boilerplate for
/// its own sake: Swift's *synthesized* `Decodable` calls `decode` rather than
/// `decodeIfPresent`, so a property with a default value still **throws** when
/// its key is absent. Python configs are routinely partial — `configs/lotus.yaml`
/// overrides four keys and nothing else — so synthesized decoding would reject
/// them, and would also break the moment the reference adds or removes a field.
/// Decoding here fills in the default instead.

extension KeyedDecodingContainer {
    /// Decode `key` if present and well-formed, otherwise use `fallback`.
    func or<T: Decodable>(_ key: Key, _ fallback: T) -> T {
        ((try? decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
    }
}

// MARK: - Preprocess

/// Paper section 2.1 — image conditioning before anything else runs.
public struct PreprocessConfig: Codable, Equatable, Sendable {
    /// Longest edge of the working image, in pixels. Everything upstream of the
    /// mesh runs at this resolution.
    public var workRes: Int = 1536

    public var claheClipLimit: Double = 2.0
    public var claheTileGrid: Int = 8
    public var applyClahe: Bool = true

    /// Paper Eq. (1): divide each segment's luminance by its own albedo, so a
    /// dark robe and a bright wall at the same depth reconstruct to the same
    /// height.
    public var albedoNormalize: Bool = true

    /// Lower clamp on rho. Near-black segments would otherwise divide by ~zero
    /// and blow up to full height.
    public var albedoFloor: Double = 0.15

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        workRes = c.or(.workRes, 1536)
        claheClipLimit = c.or(.claheClipLimit, 2.0)
        claheTileGrid = c.or(.claheTileGrid, 8)
        applyClahe = c.or(.applyClahe, true)
        albedoNormalize = c.or(.albedoNormalize, true)
        albedoFloor = c.or(.albedoFloor, 0.15)
    }
}

// MARK: - Segment

/// Automatic replacement for the paper's manual livewire tracing.
public struct SegmentConfig: Codable, Equatable, Sendable {
    public var nSegments: Int = 900
    public var compactness: Double = 12.0
    public var sigma: Double = 1.0

    /// CIE76 dE between adjacent superpixel means below which they merge.
    public var mergeThreshold: Double = 8.0
    public var minSegmentPx: Int = 200

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        nSegments = c.or(.nSegments, 900)
        compactness = c.or(.compactness, 12.0)
        sigma = c.or(.sigma, 1.0)
        mergeThreshold = c.or(.mergeThreshold, 8.0)
        minSegmentPx = c.or(.minSegmentPx, 200)
    }
}

// MARK: - Route

public struct RouteConfig: Codable, Equatable, Sendable {
    /// `auto` | `realistic` | `illustration`
    public var mode: String = "auto"

    /// At or above this score the image is routed to the illustration branch.
    public var flatnessThreshold: Double = 0.55
    public var quantizeColors: Int = 32

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mode = c.or(.mode, "auto")
        flatnessThreshold = c.or(.flatnessThreshold, 0.55)
        quantizeColors = c.or(.quantizeColors, 32)
    }
}

// MARK: - Depth

public struct DepthConfig: Codable, Equatable, Sendable {
    /// `auto` | `dav2` | `layers-classical`.
    ///
    /// The Python registry also carries `da3`, `lotus` and `illustrators_depth`.
    /// None of them ship here: the first two need a conda subprocess, and
    /// `illustrators_depth` is Adobe-licensed and excluded by decision.
    public var backend: String = "auto"

    public var device: String = "auto"
    public var dav2Model: String = "depth-anything/Depth-Anything-V2-Large-hf"

    /// Layer count for the dependency-free fallback decomposition.
    public var classicalLayers: Int = 8

    /// Set if a backend returns disparity-like output where near = low.
    public var invert: Bool = false

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        backend = c.or(.backend, "auto")
        device = c.or(.device, "auto")
        dav2Model = c.or(.dav2Model, "depth-anything/Depth-Anything-V2-Large-hf")
        classicalLayers = c.or(.classicalLayers, 8)
        invert = c.or(.invert, false)
    }
}

// MARK: - Correct

/// Stage 4. Fixes what the depth network smoothed away or quantized.
public struct CorrectConfig: Codable, Equatable, Sendable {
    public var guidedFilter: Bool = true
    public var guidedRadius: Int = 8
    public var guidedEps: Double = 1e-4

    public var deband: Bool = true

    /// A histogram bin this many times the local median counts as a
    /// quantization spike and gets monotonically refit.
    public var debandSpikeRatio: Double = 3.0

    public var despeckle: Bool = true

    /// Median filter removing isolated pixels at depth cliffs. A median is
    /// edge-preserving, so the cliff survives while the ragged pixels do not.
    public var despeckleKernel: Int = 5

    /// Illustration branch sets this. Smooths only *within* each layer, never
    /// across a layer boundary — the steps are the signal there, not an artifact.
    public var preserveLayers: Bool = false

    /// `auto` | `always` | `never` — snap depth to one constant per colour
    /// region. `auto` fires only when a continuous depth model has been run on
    /// art the router called flat, which is the one failure the illustration
    /// branch exists to prevent.
    public var layerQuantize: String = "auto"

    public var backgroundSuppress: Bool = true
    public var backgroundPercentile: Double = 5.0

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guidedFilter = c.or(.guidedFilter, true)
        guidedRadius = c.or(.guidedRadius, 8)
        guidedEps = c.or(.guidedEps, 1e-4)
        deband = c.or(.deband, true)
        debandSpikeRatio = c.or(.debandSpikeRatio, 3.0)
        despeckle = c.or(.despeckle, true)
        despeckleKernel = c.or(.despeckleKernel, 5)
        preserveLayers = c.or(.preserveLayers, false)
        layerQuantize = c.or(.layerQuantize, "auto")
        backgroundSuppress = c.or(.backgroundSuppress, true)
        backgroundPercentile = c.or(.backgroundPercentile, 5.0)
    }
}

// MARK: - Light

/// Paper Fig. 12. Scene illumination in a painting is imagined, not physical,
/// so this is an estimate with a human override.
public struct LightConfig: Codable, Equatable, Sendable {
    public var autoEstimate: Bool = true
    public var vector: [Double] = [0.3, 0.4, 0.85]

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        autoEstimate = c.or(.autoEstimate, true)
        vector = c.or(.vector, [0.3, 0.4, 0.85])
    }
}

// MARK: - Volume

/// Stage 5 — the paper's Eq. (8), extended with the AI depth term.
public struct VolumeConfig: Codable, Equatable, Sendable {
    public var lambdaAi: Double = 1.0
    public var lambdaRough: Double = 0.35
    public var lambdaMain: Double = 0.45

    /// The paper states the detail weight belongs below 0.05.
    public var lambdaDetail: Double = 0.04

    // Z_rough, section 2.3.2
    public var roughSmoothIters: Int = 60
    public var roughKernel: Int = 3

    // Z_main, section 2.3.3
    public var sfsEnabled: Bool = true

    /// lambda in Eq. (11), the regularization weight on the smoothness term.
    public var sfsSmoothness: Double = 0.6
    public var sfsIters: Int = 300
    public var sfsSorOmega: Double = 1.6

    /// Solve SFS at this resolution then upsample. The solver is
    /// O(iters * px) and the result is low-frequency, so full-res buys nothing.
    public var sfsScale: Int = 512

    /// Sweeps between integrability projections (Frankot & Chellappa).
    /// 0 disables it.
    public var sfsProjectEvery: Int = 20

    /// Pixels brighter than this percentile are treated as local maxima facing
    /// the light (Eq. 14), which is what breaks the concave/convex ambiguity.
    public var sfsMbcPercentile: Double = 98.0

    /// `gradient` (Eq. 18-20) | `brightness` (Eq. 17)
    public var detailMode: String = "gradient"

    /// Paper section 2.4: no segment may protrude past one nearer the viewer.
    public var enforceOrdering: Bool = true
    public var orderingStrength: Double = 1.0

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lambdaAi = c.or(.lambdaAi, 1.0)
        lambdaRough = c.or(.lambdaRough, 0.35)
        lambdaMain = c.or(.lambdaMain, 0.45)
        lambdaDetail = c.or(.lambdaDetail, 0.04)
        roughSmoothIters = c.or(.roughSmoothIters, 60)
        roughKernel = c.or(.roughKernel, 3)
        sfsEnabled = c.or(.sfsEnabled, true)
        sfsSmoothness = c.or(.sfsSmoothness, 0.6)
        sfsIters = c.or(.sfsIters, 300)
        sfsSorOmega = c.or(.sfsSorOmega, 1.6)
        sfsScale = c.or(.sfsScale, 512)
        sfsProjectEvery = c.or(.sfsProjectEvery, 20)
        sfsMbcPercentile = c.or(.sfsMbcPercentile, 98.0)
        detailMode = c.or(.detailMode, "gradient")
        enforceOrdering = c.or(.enforceOrdering, true)
        orderingStrength = c.or(.orderingStrength, 1.0)
    }
}

// MARK: - Mesh

public struct MeshConfig: Codable, Equatable, Sendable {
    public var plateWidthMm: Double = 200.0

    /// `nil` derives it from the image aspect ratio.
    public var plateHeightMm: Double? = nil

    /// The bas-relief Z compression — the single most important knob for
    /// tactile legibility, and the **Depth** slider. Note the reference export
    /// used 30 mm against this 8 mm default.
    public var reliefMm: Double = 8.0

    public var baseMm: Double = 3.0

    /// Declared in `config.py` and documented there, but never read by
    /// `s6_mesh.py`. Kept only so a Python-written config round-trips.
    public var borderMm: Double = 0.0
    public var borderHeightMm: Double = 2.0

    /// Height map is resampled to this many samples on its long edge before
    /// triangulation. 900 -> ~1.6M triangles before decimation.
    public var maxGrid: Int = 900

    public var decimate: Bool = true
    public var targetFaces: Int = 400_000

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        plateWidthMm = c.or(.plateWidthMm, 200.0)
        reliefMm = c.or(.reliefMm, 8.0)
        baseMm = c.or(.baseMm, 3.0)
        borderMm = c.or(.borderMm, 0.0)
        borderHeightMm = c.or(.borderHeightMm, 2.0)
        maxGrid = c.or(.maxGrid, 900)
        decimate = c.or(.decimate, true)
        targetFaces = c.or(.targetFaces, 400_000)
        plateHeightMm = c.or(.plateHeightMm, nil as Double?)
    }
}

// MARK: - Export

public struct ExportConfig: Codable, Equatable, Sendable {
    /// Fabrication deliverable.
    public var stl: Bool = true

    /// The Python also writes GLB and a Blender file. On device those are
    /// replaced by USDZ (free AR Quick Look) and dropped respectively.
    public var usdz: Bool = true

    public var heightmap: Bool = true

    /// Write every stage output. This is how a bad blend gets diagnosed, but on
    /// device it is 14 PNGs per run — developer setting only.
    public var intermediates: Bool = false

    public var report: Bool = true
    public var nozzleMm: Double = 0.4

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        stl = c.or(.stl, true)
        usdz = c.or(.usdz, true)
        heightmap = c.or(.heightmap, true)
        intermediates = c.or(.intermediates, false)
        report = c.or(.report, true)
        nozzleMm = c.or(.nozzleMm, 0.4)
    }
}

// MARK: - Root

public struct ReliefConfig: Codable, Equatable, Sendable {
    public var preprocess = PreprocessConfig()
    public var segment = SegmentConfig()
    public var route = RouteConfig()
    public var depth = DepthConfig()
    public var correct = CorrectConfig()
    public var light = LightConfig()
    public var volume = VolumeConfig()
    public var mesh = MeshConfig()
    public var export = ExportConfig()

    /// Accepted by the Python and unused there — SLIC is deterministic in
    /// scikit-image >= 0.20.
    public var seed: Int = 0

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        preprocess = c.or(.preprocess, PreprocessConfig())
        segment = c.or(.segment, SegmentConfig())
        route = c.or(.route, RouteConfig())
        depth = c.or(.depth, DepthConfig())
        correct = c.or(.correct, CorrectConfig())
        light = c.or(.light, LightConfig())
        volume = c.or(.volume, VolumeConfig())
        mesh = c.or(.mesh, MeshConfig())
        export = c.or(.export, ExportConfig())
        seed = c.or(.seed, 0)
    }

    // MARK: Coding

    /// Decoder matching what `config.py` emits via `asdict()`.
    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    public static func decode(from data: Data) throws -> ReliefConfig {
        try makeDecoder().decode(ReliefConfig.self, from: data)
    }
}
