import Foundation
import ReliefNumerics

/// Stage 2's clusters — the paper's C_i, with their albedos rho_i.
///
/// The paper obtains these by having a human trace every object outline with a
/// livewire tool, and names automating that as the single biggest available
/// improvement to the method. This is that automation: SLIC superpixels merged
/// by colour similarity in CIELAB.
///
/// The clusters matter twice over — albedo normalization (Eq. 1) divides by the
/// per-cluster albedo, and Z_rough inflates each cluster's silhouette
/// separately — which is why the region *count* has to match the reference
/// exactly, not just approximately.
public struct Segmentation: Sendable {
    public let labels: Plane      // values 0..<count, densely packed
    public let count: Int
    public let albedo: [Float]    // mean reflectance per cluster, in [0, 1]
}

public enum Segment {
    /// Mirrors `relief.segment.segment`. `rgb` is the working-resolution image
    /// in [0, 1]; `lab` is the pipeline's own CIELAB of the *unnormalised*
    /// image (SLIC normalises internally and so uses a different Lab).
    public static func segment(rgb: Plane, lab: Plane,
                               config: SegmentConfig) -> Segmentation {
        precondition(rgb.channels == 3 && lab.channels == 3)
        let n = rgb.rows * rgb.cols

        var slicLabels = [Int32](repeating: 0, count: n)
        _ = rgb.values.withUnsafeBufferPointer { src in
            slicLabels.withUnsafeMutableBufferPointer { dst in
                relief_slic(src.baseAddress!, rgb.rows, rgb.cols,
                            Int32(config.nSegments), config.compactness,
                            config.sigma, 1, dst.baseAddress!)
            }
        }

        var merged = [Int32](repeating: 0, count: n)
        // Regions are ~10^2-10^3 after merging; this bound is generous.
        let capacity = 8192
        var albedo = [Float](repeating: 0, count: capacity)
        let count = lab.values.withUnsafeBufferPointer { lb in
            slicLabels.withUnsafeBufferPointer { src in
                merged.withUnsafeMutableBufferPointer { dst in
                    albedo.withUnsafeMutableBufferPointer { alb in
                        relief_merge_regions(lb.baseAddress!, src.baseAddress!,
                                             lab.rows, lab.cols,
                                             config.mergeThreshold,
                                             Int32(config.minSegmentPx),
                                             dst.baseAddress!, alb.baseAddress!,
                                             Int32(capacity))
                    }
                }
            }
        }

        return Segmentation(
            labels: Plane(rows: rgb.rows, cols: rgb.cols,
                          values: merged.map(Float.init)),
            count: Int(count),
            albedo: Array(albedo.prefix(Int(count))))
    }
}
