import Foundation
import ReliefNumerics

/// DINOv2's position embeddings, computed outside the Core ML graph.
///
/// They had to come out of the model: `interpolate_pos_encoding` resizes them
/// with `mode="bicubic"`, and coremltools has no `upsample_bicubic2d` — every
/// conversion path died there. They depend only on the input size, never on
/// image content, so they do not belong inside the model in the first place.
///
/// The app therefore ships the fixed 37×37×1024 grid and does this resize
/// itself, handing the result to the model as a second input.
public struct PositionEmbedding {
    public static let grid = 37          // 518 / patch 14 — DINOv2's training grid
    public static let embedDim = 1024    // ViT-L
    public static let patch = 14

    /// `[1, 1370, 1024]`: one class token followed by the 37×37 patch grid.
    private let base: [Float]

    public init(base: [Float]) {
        precondition(base.count == (Self.grid * Self.grid + 1) * Self.embedDim,
                     "position embedding should be 1370 x 1024")
        self.base = base
    }

    public init?(contentsOf url: URL) {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let count = data.count / MemoryLayout<Float>.size
        let values: [Float] = data.withUnsafeBytes {
            Array(UnsafeBufferPointer(
                start: $0.baseAddress!.assumingMemoryBound(to: Float.self),
                count: count))
        }
        guard count == (Self.grid * Self.grid + 1) * Self.embedDim else { return nil }
        self.init(base: values)
    }

    /// The embedding for a given model input size, as `[1, tokens, 1024]`
    /// flattened. `height` and `width` are the padded multiple-of-14 tensor
    /// dimensions, not the original image size.
    public func embedding(height: Int, width: Int) -> [Float] {
        let gh = height / Self.patch, gw = width / Self.patch
        let dim = Self.embedDim

        // The class token passes through untouched; only the patch grid is
        // resized.
        var out = [Float](repeating: 0, count: (gh * gw + 1) * dim)
        for c in 0..<dim { out[c] = base[c] }

        if gh == Self.grid && gw == Self.grid {
            for i in 0..<(Self.grid * Self.grid * dim) { out[dim + i] = base[dim + i] }
            return out
        }

        let patchGrid = Array(base[dim...])
        var resized = [Float](repeating: 0, count: gh * gw * dim)
        patchGrid.withUnsafeBufferPointer { src in
            resized.withUnsafeMutableBufferPointer { dst in
                relief_resize_bicubic_channels(src.baseAddress!, dst.baseAddress!,
                                               Int32(Self.grid), Int32(Self.grid),
                                               Int32(gh), Int32(gw), Int32(dim))
            }
        }
        for i in 0..<resized.count { out[dim + i] = resized[i] }
        return out
    }

    /// The tensor size `DPTImageProcessor` would produce for an image.
    ///
    /// **Not** 518×518. `keep_aspect_ratio: true` puts the *short* side at 518
    /// and scales the long side to preserve aspect, rounded to a multiple of 14.
    /// Feeding a squashed square instead measures up to 0.60 max absolute error
    /// on a [0,1] depth map — 17 mm of misplaced depth on a 30 mm relief.
    public static func processorSize(imageHeight: Int, imageWidth: Int,
                                     target: Int = 518,
                                     multiple: Int = 14) -> (height: Int, width: Int) {
        var scaleH = Double(target) / Double(imageHeight)
        var scaleW = Double(target) / Double(imageWidth)
        if abs(1 - scaleW) < abs(1 - scaleH) { scaleH = scaleW } else { scaleW = scaleH }
        func constrain(_ v: Double) -> Int {
            Swift.max(multiple, Int((v / Double(multiple)).rounded()) * multiple)
        }
        return (constrain(scaleH * Double(imageHeight)),
                constrain(scaleW * Double(imageWidth)))
    }
}
