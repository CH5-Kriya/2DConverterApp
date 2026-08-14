import Foundation
import ReliefNumerics

/// Stage 5 — volume reconstruction, the paper's Eq. (8).
///
/// This is where a tactile model separates from a depth visualization. A
/// monocular depth network places things correctly in space but renders each of
/// them as a smooth blob: run a finger over its output and a face reads as an
/// egg. The answer is to build height maps with *different* failure modes and
/// blend them.
public enum Volume {

    /// The SFS reconstruction domain D.
    ///
    /// Background was already pushed to zero in stage 4, so anything still
    /// above the floor is subject. If that leaves almost nothing — a flat
    /// composition with no clear far field — fall back to the whole frame
    /// rather than reconstructing a sliver.
    public static func foreground(depth: Plane, floor: Float = 1e-3) -> [UInt8] {
        let mask = depth.values.map { $0 > floor ? UInt8(1) : UInt8(0) }
        let coverage = Double(mask.reduce(0) { $0 + Int($1) }) / Double(mask.count)
        return coverage < 0.1 ? [UInt8](repeating: 1, count: mask.count) : mask
    }

    /// Z_rough — each region inflated like a balloon. Ignores shading entirely,
    /// so diffuse light cannot corrupt it; gross volume only.
    public static func inflate(labels: Plane, foreground: [UInt8]?,
                               iters: Int, kernel: Int) -> Plane {
        let n = labels.rows * labels.cols
        let ints = labels.values.map { Int32($0) }
        var out = [Float](repeating: 0, count: n)
        ints.withUnsafeBufferPointer { lb in
            out.withUnsafeMutableBufferPointer { dst in
                if let fg = foreground {
                    fg.withUnsafeBufferPointer { f in
                        relief_inflate(lb.baseAddress!, f.baseAddress!,
                                       dst.baseAddress!, labels.rows, labels.cols,
                                       Int32(iters), Int32(kernel))
                    }
                } else {
                    relief_inflate(lb.baseAddress!, nil, dst.baseAddress!,
                                   labels.rows, labels.cols,
                                   Int32(iters), Int32(kernel))
                }
            }
        }
        return Plane(rows: labels.rows, cols: labels.cols, values: out)
    }

    /// Z_detail — the finest surface texture, from the brightness gradient.
    /// Alone it is a picture rather than a shape, which is why the paper caps
    /// its blend weight below 0.05.
    public static func detail(brightness: Plane, mode: String) -> Plane {
        var out = [Float](repeating: 0, count: brightness.count)
        if mode == "brightness" { return normalize01(brightness) }
        brightness.values.withUnsafeBufferPointer { src in
            out.withUnsafeMutableBufferPointer { dst in
                relief_detail_gradient(src.baseAddress!, dst.baseAddress!,
                                       brightness.rows, brightness.cols)
            }
        }
        return Plane(rows: brightness.rows, cols: brightness.cols, values: out)
    }


    /// Apparent light direction, from where the highlights sit.
    /// Returns the unit vector and a 0–1 confidence; below 0.05 the caller
    /// falls back to the configured vector.
    public static func estimateLight(brightness: Plane, mask: [UInt8],
                                     elevation: Float = 0.75)
        -> (vector: [Float], confidence: Float) {
        var vec = [Float](repeating: 0, count: 3)
        var conf: Float = 0
        brightness.values.withUnsafeBufferPointer { img in
            mask.withUnsafeBufferPointer { m in
                vec.withUnsafeMutableBufferPointer { v in
                    relief_estimate_light(img.baseAddress!, m.baseAddress!,
                                          brightness.rows, brightness.cols,
                                          elevation, v.baseAddress!, &conf)
                }
            }
        }
        return (vec, conf)
    }

    /// Z_main — shape from shading. The one stage here that is iterative, and
    /// so the one whose tolerance is a correlation plus a max error rather than
    /// bit-exactness.
    public static func shapeFromShading(brightness: Plane, light: [Float],
                                        mask: [UInt8], initHeight: Plane?,
                                        config: VolumeConfig) -> Plane {
        var out = [Float](repeating: 0, count: brightness.count)
        // The paper is explicit that the solve only behaves when seeded from a
        // plausible surface — Z_rough. An empty array stands in for "no seed"
        // so the pointer plumbing stays a single straight-line call.
        let seed: [Float] = initHeight?.values ?? []
        out.withUnsafeMutableBufferPointer { dst in
            brightness.values.withUnsafeBufferPointer { img in
                light.withUnsafeBufferPointer { l in
                    mask.withUnsafeBufferPointer { m in
                        seed.withUnsafeBufferPointer { ih in
                            relief_shape_from_shading(
                                img.baseAddress!, l.baseAddress!, m.baseAddress!,
                                seed.isEmpty ? nil : ih.baseAddress!,
                                dst.baseAddress!,
                                brightness.rows, brightness.cols,
                                Float(config.sfsSmoothness), Int32(config.sfsIters),
                                Float(config.sfsSorOmega), config.sfsMbcPercentile,
                                Int32(config.sfsScale), Int32(config.sfsProjectEvery))
                        }
                    }
                }
            }
        }
        return Plane(rows: brightness.rows, cols: brightness.cols, values: out)
    }

    /// Paper section 2.4 — no segment may protrude past one nearer the viewer.
    /// This is the **Outline** slider.
    static let orderingHeadroom: Float = 0.35

    public static func enforceOrdering(height: Plane, zAi: Plane,
                                       labels: Plane, regionCount: Int,
                                       strength: Float) -> Plane {
        let n = height.count
        var centres = [Double](repeating: 0, count: regionCount)
        var counts = [Double](repeating: 0, count: regionCount)
        var lows = [Float](repeating: .greatestFiniteMagnitude, count: regionCount)
        var highs = [Float](repeating: -.greatestFiniteMagnitude, count: regionCount)

        for i in 0..<n {
            let k = Int(labels.values[i])
            centres[k] += Double(zAi.values[i])
            counts[k] += 1
            lows[k] = Swift.min(lows[k], height.values[i])
            highs[k] = Swift.max(highs[k], height.values[i])
        }

        var scales = [Float](repeating: 1, count: regionCount)
        var lowOut = [Float](repeating: 0, count: regionCount)
        for k in 0..<regionCount {
            let centre = Float(centres[k] / Swift.max(counts[k], 1))
            let ceiling = Swift.min(Swift.max(centre + orderingHeadroom, 0), 1)
            lowOut[k] = lows[k]
            // Only actual violations are compressed; regions already inside
            // their ceiling are left alone.
            if highs[k] > ceiling {
                let span = Swift.max(highs[k] - lows[k], 1e-6)
                let allowed = Swift.max(ceiling - lows[k], 0)
                scales[k] = allowed / span
            }
        }

        var out = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let k = Int(labels.values[i])
            let compressed = lowOut[k] + (height.values[i] - lowOut[k]) * scales[k]
            out[i] = (1 - strength) * height.values[i] + strength * compressed
        }
        return Plane(rows: height.rows, cols: height.cols, values: out)
    }

    public static func normalize01(_ plane: Plane, robust: Bool = false) -> Plane {
        var out = [Float](repeating: 0, count: plane.count)
        plane.values.withUnsafeBufferPointer { src in
            out.withUnsafeMutableBufferPointer { dst in
                relief_normalize01(src.baseAddress!, dst.baseAddress!,
                                   plane.count, robust ? 1 : 0)
            }
        }
        return Plane(rows: plane.rows, cols: plane.cols,
                     channels: plane.channels, values: out)
    }
}
