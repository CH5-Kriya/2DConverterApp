import Foundation
import simd

/// The exported solid, ready for a renderer: positions, normals and indices,
/// normalised into scene units and centred on the origin.
///
/// The geometry here is not an approximation of the STL — it *is* the STL's
/// geometry, straight out of `Mesh.build`. An earlier version of this file
/// triangulated its own coarse surface instead, which is why the preview and
/// the exported file did not look like the same object.
public struct ReliefPreviewMesh: Sendable {
    /// Identity of this snapshot, so the view can tell a genuinely new mesh
    /// from a redraw and rebuild GPU resources only when one actually arrives.
    public let id = UUID()

    public var positions: [SIMD3<Float>]
    public var normals: [SIMD3<Float>]
    public var indices: [UInt32]

    /// Size of the normalised mesh along each axis. The camera needs it to work
    /// out how far back it has to stand for the plate to fit the viewport.
    public var extent: SIMD3<Float>

    public var widthMm: Double
    public var heightMm: Double
    public var thicknessMm: Double

    public var triangleCount: Int { indices.count / 3 }
}

public enum ReliefPreviewMeshBuilder {

    /// Largest dimension of the finished mesh, in RealityKit's metres. Framing
    /// a fixed size is what lets the camera rig be a constant instead of
    /// arithmetic over whatever plate size the config happens to carry.
    public static let sceneSize: Float = 0.30

    /// Builds the solid the exporter would write, and hands it to the renderer.
    ///
    /// Same grid, same `relief_solidify`, same `relief_fix_normals` as the STL.
    /// The one difference is that quadric decimation is skipped: it costs 3×
    /// the whole rest of the build (563 ms against 186 ms at a 900 grid) and
    /// only ever *removes* triangles, so the preview shows at least as much
    /// detail as the file — never less.
    public static func build(height: Plane, config: MeshConfig) -> ReliefPreviewMesh {
        var preview = config
        preview.decimate = false
        return make(from: Mesh.build(height: height, config: preview))
    }

    /// Converts a `SolidMesh` — interleaved doubles, Int32 indices — into the
    /// float buffers a renderer wants.
    public static func make(from solid: SolidMesh) -> ReliefPreviewMesh {
        var positions = [SIMD3<Float>](repeating: .zero, count: solid.vertexCount)
        solid.vertices.withUnsafeBufferPointer { source in
            positions.withUnsafeMutableBufferPointer { out in
                for i in 0..<out.count {
                    out[i] = SIMD3(Float(source[i * 3]),
                                   Float(source[i * 3 + 1]),
                                   Float(source[i * 3 + 2]))
                }
            }
        }

        var indices = [UInt32](repeating: 0, count: solid.faces.count)
        solid.faces.withUnsafeBufferPointer { source in
            indices.withUnsafeMutableBufferPointer { out in
                for i in 0..<out.count { out[i] = UInt32(source[i]) }
            }
        }

        let normals = vertexNormals(positions: positions, indices: indices)
        let extent = normalise(&positions, to: sceneSize)

        return ReliefPreviewMesh(
            positions: positions, normals: normals, indices: indices,
            extent: extent,
            widthMm: solid.widthMm, heightMm: solid.heightMm,
            thicknessMm: solid.thicknessMm)
    }

    // MARK: - Helpers

    /// Area-weighted vertex normals: the un-normalised cross product is already
    /// proportional to twice the triangle's area, so accumulating it weights
    /// each face by how much of the surface it actually represents.
    ///
    /// Smooth rather than per-face, even though STL stores one normal per
    /// facet. At this density the facets are smaller than a pixel, so flat
    /// shading would buy nothing but three times the vertex buffer — and on the
    /// decimated mesh it would actively misrepresent the surface, faceting
    /// regions the slicer will treat as smooth.
    private static func vertexNormals(positions: [SIMD3<Float>],
                                      indices: [UInt32]) -> [SIMD3<Float>] {
        var normals = [SIMD3<Float>](repeating: .zero, count: positions.count)

        positions.withUnsafeBufferPointer { p in
            indices.withUnsafeBufferPointer { idx in
                normals.withUnsafeMutableBufferPointer { n in
                    var f = 0
                    while f < idx.count {
                        let i0 = Int(idx[f]), i1 = Int(idx[f + 1]), i2 = Int(idx[f + 2])
                        let face = simd_cross(p[i1] - p[i0], p[i2] - p[i0])
                        n[i0] += face
                        n[i1] += face
                        n[i2] += face
                        f += 3
                    }
                }
            }
        }

        for i in normals.indices {
            let length = simd_length(normals[i])
            normals[i] = length > 0 ? normals[i] / length : SIMD3(0, 0, 1)
        }
        return normals
    }

    /// Centres the mesh on the origin and scales its longest axis to `size`,
    /// so the camera rig never has to know the plate dimensions. Returns the
    /// resulting extent along each axis.
    @discardableResult
    private static func normalise(_ positions: inout [SIMD3<Float>],
                                  to size: Float) -> SIMD3<Float> {
        guard var low = positions.first else { return .zero }
        var high = low
        for p in positions {
            low = simd_min(low, p)
            high = simd_max(high, p)
        }
        let extent = high - low
        let scale = size / max(extent.max(), .ulpOfOne)
        let centre = (high + low) / 2
        for i in positions.indices {
            positions[i] = (positions[i] - centre) * scale
        }
        return extent * scale
    }
}
