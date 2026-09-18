import CoreGraphics
import CoreML
import CoreVideo
import Foundation
import ReliefNumerics
import Vision

/// Depth Anything V2 **Small**, as Apple publishes it, at
/// `apple/coreml-depth-anything-v2-small`.
///
/// This is the model the phone and the iPad run. The large one is 640 MB and
/// CC-BY-NC; this is 50 MB and Apache-2.0, which is the difference between a
/// model that can only be carried on TestFlight and one that can ship.
///
/// It is *not* a drop-in for `CoreMLDepthBackend`, which is why it is its own
/// type rather than another filename:
///
///  * **The input is an image, not a tensor.** Apple baked the ImageNet
///    normalisation into the graph, so the model wants 8-bit RGB and does the
///    `(x - mean) / std` itself. None of `relief_dpt_preprocess` applies.
///  * **The shape is fixed at 518x392.** There is no multifunction ladder and
///    no `pos_embed` input — the position embeddings never needed interpolating
///    because there is only ever one input size. Every crop is therefore
///    *stretched* to 4:3 rather than resized on its short side, which is the
///    fidelity this model trades away. Core ML does that stretch itself, from
///    the input's `imageConstraint`, so it happens in vImage rather than here.
///  * **The output is a float16 greyscale image**, not a float32 tensor.
public final class AppleDepthBackend: DepthBackend {
    public let name = "dav2-small"

    private let modelURL: URL
    private var loaded: MLModel?
    private var compiled: URL?

    public enum Failure: LocalizedError {
        case badInput
        case badOutput(String)

        public var errorDescription: String? {
            switch self {
            case .badInput:
                return "The image could not be prepared for the depth model."
            case .badOutput(let why):
                return "The depth model returned an unexpected result (\(why))."
            }
        }
    }

    public init(modelURL: URL) { self.modelURL = modelURL }

    /// Locate the model in a bundle. Unlike the large one there is no second
    /// artifact to find — the position-embedding grid goes with the ladder.
    public static func bundled(in bundle: Bundle = .main) -> AppleDepthBackend? {
        guard let url = bundle.url(forResource: "DepthAnythingV2SmallF16",
                                   withExtension: "mlmodelc")
                     ?? bundle.url(forResource: "DepthAnythingV2SmallF16",
                                   withExtension: "mlpackage")
        else { return nil }
        return AppleDepthBackend(modelURL: url)
    }

    public func unload() { loaded = nil }

    /// Xcode compiles a bundled `.mlpackage` into `.mlmodelc` at build time; a
    /// model dropped in by hand is not compiled. Same as the large backend.
    private func model() throws -> MLModel {
        if let loaded { return loaded }
        let config = MLModelConfiguration()
        // Same simulator caveat as the large model: any compute mode that
        // includes the GPU fails Metal validation on these DPT graphs.
        #if targetEnvironment(simulator)
        config.computeUnits = .cpuOnly
        #else
        config.computeUnits = .all
        #endif
        let url: URL
        if modelURL.pathExtension == "mlmodelc" {
            url = modelURL
        } else if let done = compiled {
            url = done
        } else {
            url = try MLModel.compileModel(at: modelURL)
            compiled = url
        }
        let ml = try MLModel(contentsOf: url, configuration: config)
        loaded = ml
        return ml
    }

    public func predict(rgb: Plane, lab: Plane) throws -> DepthResult {
        let ml = try model()
        guard let source = Self.image(from: rgb),
              let constraint = ml.modelDescription
                  .inputDescriptionsByName["image"]?.imageConstraint
        else { throw Failure.badInput }

        // `.scaleFill` is the stretch. The alternatives crop the picture, which
        // would silently drop relief off the edges of anything not already 4:3.
        let pixels = try MLFeatureValue(
            cgImage: source, orientation: .up, constraint: constraint,
            options: [.cropAndScale: VNImageCropAndScaleOption.scaleFill.rawValue])
        let result = try ml.prediction(from:
            MLDictionaryFeatureProvider(dictionary: ["image": pixels]))
        guard let buffer = result.featureValue(for: "depth")?.imageBufferValue else {
            throw Failure.badOutput("no depth image")
        }

        let predicted = try Self.plane(from: buffer)
        if getenv("RELIEF_DEBUG_DEPTH") != nil {
            print("    model input  \(constraint.pixelsHigh)x\(constraint.pixelsWide)"
                  + "  from \(rgb.rows)x\(rgb.cols) (stretched)")
            print("    output \(predicted.rows)x\(predicted.cols)"
                  + "  format \(CVPixelBufferGetPixelFormatType(buffer))")
        }

        // Back to working resolution in float, before any quantisation — the
        // same reasoning as the large backend, and the same resampler.
        var upscaled = [Float](repeating: 0, count: rgb.rows * rgb.cols)
        predicted.values.withUnsafeBufferPointer { src in
            upscaled.withUnsafeMutableBufferPointer { dst in
                relief_resize_bicubic_channels(src.baseAddress!, dst.baseAddress!,
                                               Int32(predicted.rows), Int32(predicted.cols),
                                               Int32(rgb.rows), Int32(rgb.cols), 1)
            }
        }

        let depth = Volume.normalize01(
            Plane(rows: rgb.rows, cols: rgb.cols, values: upscaled))
        return DepthResult(depth: depth, backend: name, discrete: false,
                           layerCount: nil,
                           notes: "Depth Anything V2 Small, "
                                + "\(predicted.rows)x\(predicted.cols) (stretched)")
    }

    /// The working image as 8-bit RGB, at its own size — Core ML resizes.
    ///
    /// Tagged `DeviceRGB` because `ReliefImage` reads samples in the file's own
    /// space and leaves them untouched; re-tagging them as anything else here
    /// would gamut-map on the way into the model.
    static func image(from rgb: Plane) -> CGImage? {
        guard rgb.channels == 3 else { return nil }
        var bytes = [UInt8](repeating: 0, count: rgb.count)
        for i in 0..<rgb.count {
            bytes[i] = UInt8(Swift.max(0, Swift.min(1, rgb.values[i])) * 255)
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: rgb.cols, height: rgb.rows, bitsPerComponent: 8,
                       bitsPerPixel: 24, bytesPerRow: rgb.cols * 3,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true,
                       intent: .defaultIntent)
    }

    /// The float16 greyscale output as a float32 plane.
    ///
    /// **Respect `bytesPerRow`.** Core ML pads pixel-buffer rows for alignment,
    /// so reading the base address as a flat 518-wide array shifts every row
    /// progressively and shears the depth map into noise — with the right
    /// element count and the right range, so nothing downstream complains.
    static func plane(from buffer: CVPixelBuffer) throws -> Plane {
        let format = CVPixelBufferGetPixelFormatType(buffer)
        guard format == kCVPixelFormatType_OneComponent16Half else {
            throw Failure.badOutput("pixel format \(format)")
        }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else {
            throw Failure.badOutput("no base address")
        }
        let h = CVPixelBufferGetHeight(buffer)
        let w = CVPixelBufferGetWidth(buffer)
        let stride = CVPixelBufferGetBytesPerRow(buffer)

        var out = [Float](repeating: 0, count: h * w)
        for y in 0..<h {
            let row = base.advanced(by: y * stride).assumingMemoryBound(to: Float16.self)
            for x in 0..<w { out[y * w + x] = Float(row[x]) }
        }
        return Plane(rows: h, cols: w, values: out)
    }
}
