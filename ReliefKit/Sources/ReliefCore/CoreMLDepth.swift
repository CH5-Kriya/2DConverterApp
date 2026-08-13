import CoreML
import Foundation
import ReliefNumerics

/// Depth Anything V2 Large, via Core ML.
///
/// Two things had to come out of the model to make it convertible at all, and
/// both are reconstructed here:
///
///  * **Position embeddings.** DINOv2 resizes them with `mode="bicubic"`, which
///    coremltools cannot convert. They depend only on the input size, so they
///    are computed on the CPU and passed in as a second input.
///  * **A fixed output size.** The DPT head sizes its upsample with `int()`
///    casts that collapse to constants under tracing, so one traced graph would
///    emit the trace shape for *any* input — wrong for every other aspect ratio,
///    with no error raised. The shipped package is therefore *multifunction*:
///    one function per aspect bucket, all sharing a single copy of the weights
///    (15 shapes for 671 MB against 666 MB for one).
public final class CoreMLDepthBackend: DepthBackend {
    public let name = "dav2"

    private let modelURL: URL
    private let positionEmbedding: PositionEmbedding
    private var cache: [String: MLModel] = [:]

    /// Aspect buckets the package was built with. An image whose short side
    /// scales to a long side outside this list has no matching function and is
    /// handled explicitly rather than silently snapped to a wrong one.
    public static let longSides = [518, 616, 644, 728, 742, 784, 868, 1008]

    public enum Failure: LocalizedError {
        case modelMissing(URL)
        case unsupportedShape(height: Int, width: Int)
        case badOutput

        public var errorDescription: String? {
            switch self {
            case .modelMissing(let url):
                return "Depth model not found at \(url.lastPathComponent)."
            case .unsupportedShape(let h, let w):
                return "No depth function for a \(h)x\(w) input."
            case .badOutput:
                return "The depth model returned an unexpected result."
            }
        }
    }

    public init(modelURL: URL, positionEmbedding: PositionEmbedding) {
        self.modelURL = modelURL
        self.positionEmbedding = positionEmbedding
    }

    /// Locate the compiled model and the position-embedding grid in a bundle.
    public static func bundled(in bundle: Bundle = .main) -> CoreMLDepthBackend? {
        guard let model = bundle.url(forResource: "dav2_large_multifunction_f16",
                                     withExtension: "mlmodelc")
                       ?? bundle.url(forResource: "dav2_large_multifunction_f16",
                                     withExtension: "mlpackage"),
              let grid = bundle.url(forResource: "base_1x1370x1024",
                                    withExtension: "f32"),
              let pe = PositionEmbedding(contentsOf: grid) else { return nil }
        return CoreMLDepthBackend(modelURL: model, positionEmbedding: pe)
    }

    static func functionName(height: Int, width: Int) -> String { "s\(height)x\(width)" }

    private func model(for name: String) throws -> MLModel {
        if let cached = cache[name] { return cached }
        let config = MLModelConfiguration()
        config.computeUnits = .all          // let the runtime place it; static
        config.functionName = name          // shapes are what keep it on the ANE
        let loaded = try MLModel(contentsOf: modelURL, configuration: config)
        cache[name] = loaded
        return loaded
    }

    /// Free the weights. Depth is finished before the mesh stage, and at fp16
    /// this is the largest single allocation in the app.
    public func unload() { cache.removeAll() }

    public func predict(rgb: Plane, lab: Plane) throws -> DepthResult {
        let size = PositionEmbedding.processorSize(imageHeight: rgb.rows,
                                                   imageWidth: rgb.cols)
        let long = Swift.max(size.height, size.width)
        guard Self.longSides.contains(long) else {
            throw Failure.unsupportedShape(height: size.height, width: size.width)
        }

        // 1. DPTImageProcessor-equivalent preprocessing, as CHW.
        var chw = [Float](repeating: 0, count: size.height * size.width * 3)
        rgb.values.withUnsafeBufferPointer { src in
            chw.withUnsafeMutableBufferPointer { dst in
                relief_dpt_preprocess(src.baseAddress!, rgb.rows, rgb.cols,
                                      Int32(size.height), Int32(size.width),
                                      dst.baseAddress!)
            }
        }

        let pixels = try MLMultiArray(shape: [1, 3, NSNumber(value: size.height),
                                              NSNumber(value: size.width)],
                                      dataType: .float32)
        chw.withUnsafeBufferPointer { src in
            pixels.dataPointer.assumingMemoryBound(to: Float.self)
                .update(from: src.baseAddress!, count: chw.count)
        }

        // 2. The position embedding for this exact input size.
        let pe = positionEmbedding.embedding(height: size.height, width: size.width)
        let tokens = pe.count / PositionEmbedding.embedDim
        let posArray = try MLMultiArray(
            shape: [1, NSNumber(value: tokens),
                    NSNumber(value: PositionEmbedding.embedDim)],
            dataType: .float32)
        pe.withUnsafeBufferPointer { src in
            posArray.dataPointer.assumingMemoryBound(to: Float.self)
                .update(from: src.baseAddress!, count: pe.count)
        }

        // 3. Run the function matching this aspect bucket.
        let ml = try model(for: Self.functionName(height: size.height, width: size.width))
        let input = try MLDictionaryFeatureProvider(dictionary: [
            "pixel_values": MLFeatureValue(multiArray: pixels),
            "pos_embed": MLFeatureValue(multiArray: posArray),
        ])
        let result = try ml.prediction(from: input)
        guard let raw = result.featureValue(for: "predicted_depth")?.multiArrayValue
        else { throw Failure.badOutput }

        // 4. Back to working resolution **in float, before any quantization**.
        // The reference avoids the transformers pipeline helper for exactly this
        // reason: it returns 8-bit, and 256 levels over an 8 mm relief is a
        // 31 micron step — coarse enough to feel as banding.
        let count = raw.count
        var predicted = [Float](repeating: 0, count: count)
        let ptr = raw.dataPointer.assumingMemoryBound(to: Float.self)
        for i in 0..<count { predicted[i] = ptr[i] }

        var upscaled = [Float](repeating: 0, count: rgb.rows * rgb.cols)
        predicted.withUnsafeBufferPointer { src in
            upscaled.withUnsafeMutableBufferPointer { dst in
                relief_resize_bicubic_channels(src.baseAddress!, dst.baseAddress!,
                                               Int32(size.height), Int32(size.width),
                                               Int32(rgb.rows), Int32(rgb.cols), 1)
            }
        }

        let depth = Volume.normalize01(
            Plane(rows: rgb.rows, cols: rgb.cols, values: upscaled))
        return DepthResult(depth: depth, backend: name, discrete: false,
                           layerCount: nil,
                           notes: "Depth Anything V2 Large, \(size.height)x\(size.width)")
    }
}
