import Foundation
import ReliefCore

/// Pre-decimation mesh check against `06_mesh_predecimate.json`.
func checkMeshes(root: URL) {
    struct Expected: Codable {
        let grid: [Int]; let plate_w: Double; let plate_h: Double
        let vertices: Int; let faces: Int; let volume_mm3: Double
        let watertight: Bool; let body_count: Int
    }
    guard let fixtures = try? GoldenFixture.discover(in: root) else { return }
    print("\n--- stage 6: solidify (pre-decimation) ---")
    for fixture in fixtures {
        let url = fixture.directory.appendingPathComponent("06_mesh_predecimate.json")
        guard let data = try? Data(contentsOf: url),
              let exp = try? JSONDecoder().decode(Expected.self, from: data),
              let height = try? fixture.plane("06_height_final") else { continue }

        // Pre-decimation first, so solidify is measured on its own.
        var rawCfg = fixture.manifest.config.mesh
        rawCfg.decimate = false
        let m = Mesh.build(height: height, config: rawCfg)
        let volErr = abs(m.volumeMm3 - exp.volume_mm3) / exp.volume_mm3 * 100
        let ok = m.rows == exp.grid[0] && m.cols == exp.grid[1]
              && m.vertexCount == exp.vertices && m.faceCount == exp.faces
              && volErr < 0.01
        // Round-trip the STL: a file whose triangle count or geometry does not
        // survive writing is worse than no file, because a slicer will happily
        // open it.
        // Full stage 6 including decimation, against the reference's own
        // post-decimation numbers in the manifest.
        let dec = Mesh.decimate(m, targetFaces: fixture.manifest.config.mesh.targetFaces)
        let sc = fixture.manifest.scalars
        let dVolErr = abs(dec.mesh.volumeMm3 - sc.meshVolumeMm3) / sc.meshVolumeMm3 * 100
        print(String(format: "    decimated f %d/%d  v %d/%d  vol %.3f vs %.3f (%.4f%%)  watertight %@%@",
                     dec.mesh.faceCount, sc.meshFaces,
                     dec.mesh.vertexCount, sc.meshVertices,
                     dec.mesh.volumeMm3, sc.meshVolumeMm3, dVolErr,
                     dec.mesh.isWatertight ? "yes" : "NO",
                     dec.note.map { " [\($0)]" } ?? ""))

        let stl = Export.binarySTL(dec.mesh)
        let declared = stl.withUnsafeBytes { $0.load(fromByteOffset: 80, as: UInt32.self) }
        let stlOK = Int(UInt32(littleEndian: declared)) == dec.mesh.faceCount
                 && stl.count == 84 + dec.mesh.faceCount * 50
        let wt = dec.mesh.isWatertight

        print(String(format: "    stl %@ %d bytes, %d triangles   watertight %@",
                     stlOK ? "ok" : "FAIL", stl.count, dec.mesh.faceCount,
                     wt ? "yes" : "NO"))
        print(String(format: "%-24s %@ grid %dx%d  v %d/%d  f %d/%d  vol %.3f vs %.3f (%.5f%%)",
                     (fixture.sample as NSString).utf8String!, ok ? "ok  " : "FAIL",
                     m.rows, m.cols, m.vertexCount, exp.vertices,
                     m.faceCount, exp.faces, m.volumeMm3, exp.volume_mm3, volErr))
    }
}
