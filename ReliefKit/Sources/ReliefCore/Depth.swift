import Foundation

/// Stage 3 — depth estimation.
///
/// The Python keeps a registry of backends; this port carries two of them.
/// `dav2` (Core ML, Depth Anything V2 Large) is the real one. `layersClassical`
/// is the dependency-free fallback, so a missing or unloadable model degrades
/// output quality instead of blocking the run.
public struct DepthResult: Sendable {
    public let depth: Plane        // [0, 1], 1 = nearest the viewer
    public let backend: String
    public let discrete: Bool      // layer-index output; steps are the signal
    public let layerCount: Int?
    public let notes: String
}

public protocol DepthBackend {
    var name: String { get }
    func predict(rgb: Plane, lab: Plane) throws -> DepthResult
}

/// Pure-numerics layer decomposition. Always available.
///
/// This is a **heuristic, not a model**. It ranks colour regions into a
/// stacking order using three compositional priors that hold across most framed
/// artwork: regions lower in the frame are usually nearer (ground plane),
/// larger regions are usually background, and regions touching the frame edge
/// are usually background.
public struct ClassicalLayersBackend: DepthBackend {
    public let name = "layers-classical"
    public let layerCount: Int

    public init(layerCount: Int = 8) { self.layerCount = layerCount }

    public func predict(rgb: Plane, lab: Plane) throws -> DepthResult {
        // Re-segments more coarsely than the main pipeline: this wants object-
        // sized regions to rank, not superpixels.
        var cfg = SegmentConfig()
        cfg.mergeThreshold = 14.0
        cfg.minSegmentPx = 400
        let seg = Segment.segment(rgb: rgb, lab: lab, config: cfg)

        let h = rgb.rows, w = rgb.cols, n = seg.count
        var counts = [Double](repeating: 0, count: n)
        var centroidY = [Double](repeating: 0, count: n)
        var borderCount = [Double](repeating: 0, count: n)

        for y in 0..<h {
            let yy = h > 1 ? Double(y) / Double(h - 1) : 0
            for x in 0..<w {
                let k = Int(seg.labels.values[y * w + x])
                counts[k] += 1
                centroidY[k] += yy
                if y == 0 || y == h - 1 || x == 0 || x == w - 1 {
                    borderCount[k] += 1
                }
            }
        }

        let area = Double(h * w)
        var nearness = [(value: Double, index: Int)]()
        nearness.reserveCapacity(n)
        for k in 0..<n {
            let c = Swift.max(counts[k], 1)
            let cy = centroidY[k] / c
            let areaFrac = c / area
            let borderFrac = borderCount[k] / c
            let v = 0.5 * cy
                  + 0.3 * (1.0 - Swift.min(Swift.max(areaFrac * 4.0, 0), 1))
                  + 0.2 * (1.0 - Swift.min(Swift.max(borderFrac * 10.0, 0), 1))
            nearness.append((v, k))
        }

        // Rank into discrete layers so the output is piecewise-flat like the
        // real model's, not a continuous ramp.
        let ranked = nearness.enumerated()
            .sorted { $0.element.value < $1.element.value }
        var rank = [Double](repeating: 0, count: n)
        for (position, entry) in ranked.enumerated() { rank[entry.offset] = Double(position) }

        let layers = Swift.max(2, layerCount)
        var layerOf = [Float](repeating: 0, count: n)
        for k in 0..<n {
            let l = (rank[k] / Double(Swift.max(1, n)) * Double(layers)).rounded(.down)
            layerOf[k] = Float(Swift.min(Swift.max(l, 0), Double(layers - 1)))
        }

        let denom = Float(layers - 1)
        let depth = seg.labels.values.map { layerOf[Int($0)] / denom }
        return DepthResult(depth: Plane(rows: h, cols: w, values: depth),
                           backend: name, discrete: true, layerCount: layers,
                           notes: "heuristic ordering, not a learned model")
    }
}
