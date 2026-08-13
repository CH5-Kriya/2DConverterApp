import Foundation
import ReliefNumerics

/// Stage 6 — the height field closed into a printable solid.
public struct SolidMesh {
    public var vertices: [Double]   // interleaved x, y, z
    public var faces: [Int32]       // interleaved triangle indices
    public let rows: Int
    public let cols: Int
    public let widthMm: Double
    public let heightMm: Double
    public let thicknessMm: Double
    public let mmPerPixel: Double

    public var vertexCount: Int { vertices.count / 3 }
    public var faceCount: Int { faces.count / 3 }

    public var isWatertight: Bool {
        faces.withUnsafeBufferPointer {
            relief_mesh_is_watertight($0.baseAddress!, faces.count / 3) != 0
        }
    }

    public var volumeMm3: Double {
        vertices.withUnsafeBufferPointer { v in
            faces.withUnsafeBufferPointer { f in
                relief_mesh_volume(v.baseAddress!, f.baseAddress!, faces.count / 3)
            }
        }
    }
}

public enum Mesh {
    public static func build(height: Plane, config: MeshConfig) -> SolidMesh {
        // Resample to the print grid first: tactile output is bounded by the
        // grid and the nozzle, so carrying full working resolution into the
        // mesh buys nothing.
        var grid = [Float](repeating: 0, count: height.count)
        var rows: size_t = 0, cols: size_t = 0
        height.values.withUnsafeBufferPointer { src in
            grid.withUnsafeMutableBufferPointer { dst in
                _ = relief_resample_height(src.baseAddress!, height.rows,
                                           height.cols, Int32(config.maxGrid),
                                           dst.baseAddress!, &rows, &cols)
            }
        }
        let r = Int(rows), c = Int(cols)
        grid = Array(grid.prefix(r * c))

        let plateW = config.plateWidthMm
        let plateH = config.plateHeightMm ?? plateW * Double(r) / Double(c)

        var vCount: size_t = 0, fCount: size_t = 0
        relief_solid_counts(rows, cols, &vCount, &fCount)

        var vertices = [Double](repeating: 0, count: Int(vCount) * 3)
        var faces = [Int32](repeating: 0, count: Int(fCount) * 3)
        grid.withUnsafeBufferPointer { g in
            vertices.withUnsafeMutableBufferPointer { v in
                faces.withUnsafeMutableBufferPointer { f in
                    relief_solidify(g.baseAddress!, rows, cols, plateW, plateH,
                                    config.baseMm, config.reliefMm,
                                    v.baseAddress!, f.baseAddress!)
                }
            }
        }

        // `_solidify` does not emit consistently-wound faces; the reference
        // relies on trimesh to repair that, so the port must too.
        vertices.withUnsafeBufferPointer { v in
            faces.withUnsafeMutableBufferPointer { f in
                relief_fix_normals(v.baseAddress!, f.baseAddress!,
                                   size_t(f.count / 3), size_t(v.count / 3))
            }
        }

        var solid = SolidMesh(vertices: vertices, faces: faces, rows: r, cols: c,
                              widthMm: plateW, heightMm: plateH,
                              thicknessMm: config.baseMm + config.reliefMm,
                              mmPerPixel: plateW / Double(max(1, c)))

        if config.decimate && solid.faceCount > config.targetFaces {
            solid = decimate(solid, targetFaces: config.targetFaces).mesh
        }
        return solid
    }

    /// Quadric error collapses flat regions hard and leaves detailed ones
    /// dense, which is exactly what is wanted here: the back plate and
    /// background cost almost nothing while faces and drapery keep their
    /// triangles.
    ///
    /// Aggressive reductions can pinch the thin wall band into non-manifold
    /// edges, so **each result is checked and the target backed off** rather
    /// than shipping a mesh a slicer would silently misread. A non-watertight
    /// STL is a failure that only shows up at the printer.
    public static func decimate(_ mesh: SolidMesh, targetFaces: Int)
        -> (mesh: SolidMesh, note: String?) {
        let original = mesh.faceCount

        for multiplier in [1, 2, 4] {
            let goal = Swift.min(original - 1, targetFaces * multiplier)
            if goal <= 0 { break }

            var outV = [Double](repeating: 0, count: mesh.vertices.count)
            var outF = [Int32](repeating: 0, count: mesh.faces.count)
            var vCount: size_t = 0
            let fCount = mesh.vertices.withUnsafeBufferPointer { v in
                mesh.faces.withUnsafeBufferPointer { f in
                    outV.withUnsafeMutableBufferPointer { ov in
                        outF.withUnsafeMutableBufferPointer { of in
                            relief_decimate(v.baseAddress!, f.baseAddress!,
                                            size_t(mesh.vertexCount),
                                            size_t(original), size_t(goal), 7.0,
                                            ov.baseAddress!, of.baseAddress!,
                                            &vCount)
                        }
                    }
                }
            }

            var candidate = SolidMesh(
                vertices: Array(outV.prefix(Int(vCount) * 3)),
                faces: Array(outF.prefix(Int(fCount) * 3)),
                rows: mesh.rows, cols: mesh.cols, widthMm: mesh.widthMm,
                heightMm: mesh.heightMm, thicknessMm: mesh.thicknessMm,
                mmPerPixel: mesh.mmPerPixel)

            candidate.vertices.withUnsafeBufferPointer { v in
                candidate.faces.withUnsafeMutableBufferPointer { f in
                    relief_fix_normals(v.baseAddress!, f.baseAddress!,
                                       size_t(f.count / 3), size_t(v.count / 3))
                }
            }

            if candidate.isWatertight {
                let note = multiplier == 1 ? nil
                    : "decimation backed off to \(goal) faces to stay watertight"
                return (candidate, note)
            }
        }
        return (mesh, "decimation broke watertightness at every target; "
                    + "kept the dense mesh")
    }
}
