import Foundation

/// Reader for the golden fixtures written by `scripts/dump_fixtures.py`.
///
/// The Python pipeline is the specification for this port, so every stage is
/// judged against recorded reference arrays rather than against how it looks.
/// Arrays are raw little-endian C-order with no header; `manifest.json` carries
/// the shape, dtype and the scalars.

public struct FixtureArray: Codable, Equatable, Sendable {
    public let file: String
    public let dtype: String
    public let shape: [Int]
    public let bytes: Int
    public let min: Double
    public let max: Double
    public let mean: Double
}

public struct FixtureScalars: Codable, Equatable, Sendable {
    public let imageShape: [Int]
    public let routeMode: String
    public let routeScore: Double
    public let routeForced: Bool
    public let routeMetrics: [String: Double]
    public let segmentRegions: Int
    public let depthBackend: String
    public let depthDiscrete: Bool
    public let lightVector: [Double]
    public let meshWidthMm: Double
    public let meshHeightMm: Double
    public let meshThicknessMm: Double
    public let meshMmPerPixel: Double
    public let meshWatertight: Bool
    public let meshBodyCount: Int
    public let meshVolumeMm3: Double
    public let meshVertices: Int
    public let meshFaces: Int
}

public struct FixtureManifest: Codable, Sendable {
    public let sample: String
    public let source: String
    public let arrays: [String: FixtureArray]
    public let scalars: FixtureScalars
    public let notes: [String]
    public let warnings: [String]
    public let config: ReliefConfig
}

/// A stage-boundary array loaded into memory, always as `Float`.
///
/// Label images are stored as int32 and converted on load: comparisons are
/// per-element equality either way, and carrying one element type keeps the
/// comparison code from forking.
public struct Plane: Sendable {
    public let rows: Int
    public let cols: Int
    /// 1 for a height map or label image, 3 for `00_input` (RGB) and `01_lab`.
    public let channels: Int
    /// Interleaved, C-order: `values[(r * cols + c) * channels + ch]`.
    public let values: [Float]

    public init(rows: Int, cols: Int, channels: Int = 1, values: [Float]) {
        precondition(values.count == rows * cols * channels,
                     "plane is \(rows)x\(cols)x\(channels) but has \(values.count) values")
        self.rows = rows
        self.cols = cols
        self.channels = channels
        self.values = values
    }

    public var count: Int { values.count }

    /// Extract one channel as a single-channel plane.
    public func channel(_ index: Int) -> Plane {
        precondition(index < channels, "no channel \(index) in a \(channels)-channel plane")
        guard channels > 1 else { return self }
        var out = [Float](repeating: 0, count: rows * cols)
        for i in 0..<(rows * cols) { out[i] = values[i * channels + index] }
        return Plane(rows: rows, cols: cols, values: out)
    }

    public var shapeDescription: String {
        channels > 1 ? "\(rows)x\(cols)x\(channels)" : "\(rows)x\(cols)"
    }
}

public enum FixtureError: Error, CustomStringConvertible {
    case missingArray(String)
    case unsupportedDType(String)
    case sizeMismatch(name: String, expected: Int, got: Int)
    case unsupportedShape(name: String, shape: [Int])

    public var description: String {
        switch self {
        case .missingArray(let name):
            return "fixture has no array named '\(name)'"
        case .unsupportedDType(let d):
            return "unsupported fixture dtype '\(d)'"
        case .sizeMismatch(let name, let expected, let got):
            return "'\(name)' should be \(expected) bytes on disk, found \(got)"
        case .unsupportedShape(let name, let shape):
            return "'\(name)' has unsupported shape \(shape)"
        }
    }
}

public struct GoldenFixture {
    public let directory: URL
    public let manifest: FixtureManifest

    public init(directory: URL) throws {
        self.directory = directory
        let data = try Data(contentsOf: directory.appendingPathComponent("manifest.json"))
        self.manifest = try ReliefConfig.makeDecoder().decode(FixtureManifest.self, from: data)
    }

    public var sample: String { manifest.sample }

    public var arrayNames: [String] { manifest.arrays.keys.sorted() }

    /// Load a stage-boundary array by name, e.g. `"06_height_final"`.
    public func plane(_ name: String) throws -> Plane {
        guard let meta = manifest.arrays[name] else {
            throw FixtureError.missingArray(name)
        }
        let url = directory.appendingPathComponent(meta.file)
        let raw = try Data(contentsOf: url)
        guard raw.count == meta.bytes else {
            throw FixtureError.sizeMismatch(name: name, expected: meta.bytes,
                                            got: raw.count)
        }

        let count = meta.shape.reduce(1, *)
        let values: [Float]
        switch meta.dtype {
        case "float32":
            values = raw.withUnsafeBytes { buf in
                Array(UnsafeBufferPointer(
                    start: buf.baseAddress!.assumingMemoryBound(to: Float32.self),
                    count: count))
            }
        case "int32":
            values = raw.withUnsafeBytes { buf in
                UnsafeBufferPointer(
                    start: buf.baseAddress!.assumingMemoryBound(to: Int32.self),
                    count: count).map(Float.init)
            }
        default:
            throw FixtureError.unsupportedDType(meta.dtype)
        }

        // Shapes seen in practice: [n] for per-region albedo, [H, W] for the
        // height maps and label image, [H, W, 3] for `00_input` and `01_lab`.
        switch meta.shape.count {
        case 1:
            return Plane(rows: 1, cols: count, values: values)
        case 2:
            return Plane(rows: meta.shape[0], cols: meta.shape[1], values: values)
        case 3:
            return Plane(rows: meta.shape[0], cols: meta.shape[1],
                         channels: meta.shape[2], values: values)
        default:
            throw FixtureError.unsupportedShape(name: name, shape: meta.shape)
        }
    }

    /// Every fixture directory under `root`, sorted by name.
    public static func discover(in root: URL) throws -> [GoldenFixture] {
        let entries = try FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey])
        return try entries
            .filter { FileManager.default.fileExists(
                atPath: $0.appendingPathComponent("manifest.json").path) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            // A directory can hold a manifest that is not a stage fixture
            // (the DPT reference tensors, for one); skip rather than throw.
            .compactMap { try? GoldenFixture(directory: $0) }
    }
}
