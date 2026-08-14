import Foundation

/// Stage 7 — the deliverables.
///
/// The Python also writes GLB and a Blender file. On device those are replaced
/// by USDZ (free AR Quick Look) and dropped respectively; the Blender export
/// shells out to a subprocess, which has no iOS equivalent.
public enum Export {

    /// Binary STL — the fabrication deliverable, straight to a slicer.
    ///
    /// The format is an 80-byte header, a face count, then a 50-byte record per
    /// triangle: a normal, three vertices, and two padding bytes. Everything is
    /// little-endian float32, which is the one place this pipeline deliberately
    /// drops to single precision — the format has no other option.
    public static func binarySTL(_ mesh: SolidMesh,
                                 header: String = "relief") -> Data {
        let faceCount = mesh.faceCount
        var data = Data(capacity: 84 + faceCount * 50)

        var head = [UInt8](repeating: 0, count: 80)
        for (i, b) in header.utf8.prefix(79).enumerated() { head[i] = b }
        data.append(contentsOf: head)

        var count = UInt32(faceCount).littleEndian
        withUnsafeBytes(of: &count) { data.append(contentsOf: $0) }

        func appendFloat(_ v: Double) {
            var f = Float(v).bitPattern.littleEndian
            withUnsafeBytes(of: &f) { data.append(contentsOf: $0) }
        }

        for f in 0..<faceCount {
            let i0 = Int(mesh.faces[f * 3 + 0]) * 3
            let i1 = Int(mesh.faces[f * 3 + 1]) * 3
            let i2 = Int(mesh.faces[f * 3 + 2]) * 3

            let ax = mesh.vertices[i0], ay = mesh.vertices[i0 + 1], az = mesh.vertices[i0 + 2]
            let bx = mesh.vertices[i1], by = mesh.vertices[i1 + 1], bz = mesh.vertices[i1 + 2]
            let cx = mesh.vertices[i2], cy = mesh.vertices[i2 + 1], cz = mesh.vertices[i2 + 2]

            // Face normal from the winding, which `fix_normals` has already
            // made consistent and outward.
            let ux = bx - ax, uy = by - ay, uz = bz - az
            let vx = cx - ax, vy = cy - ay, vz = cz - az
            var nx = uy * vz - uz * vy
            var ny = uz * vx - ux * vz
            var nz = ux * vy - uy * vx
            let len = (nx * nx + ny * ny + nz * nz).squareRoot()
            if len > 0 { nx /= len; ny /= len; nz /= len }

            appendFloat(nx); appendFloat(ny); appendFloat(nz)
            appendFloat(ax); appendFloat(ay); appendFloat(az)
            appendFloat(bx); appendFloat(by); appendFloat(bz)
            appendFloat(cx); appendFloat(cy); appendFloat(cz)
            data.append(contentsOf: [0, 0])  // attribute byte count
        }
        return data
    }

    /// 16-bit greyscale height map, for a hand-retouching pass in other tools.
    ///
    /// 16-bit on purpose: at 8-bit, 256 levels across an 8 mm relief gives
    /// 31 micron steps — coarse enough to *feel* as banding under a fingertip.
    public static func heightMap16(_ height: Plane) -> [UInt16] {
        let normalized = Volume.normalize01(height)
        return normalized.values.map { UInt16(max(0, min(1, $0)) * 65535.0) }
    }

    /// Warnings a slicer would not give you. Mirrors `s6_mesh.check_printable`.
    public static func checkPrintable(_ mesh: SolidMesh,
                                      nozzleMm: Double) -> [String] {
        var warnings: [String] = []
        if !mesh.isWatertight {
            warnings.append("mesh is not watertight — a slicer will misread it")
        }
        if mesh.volumeMm3 <= 0 {
            warnings.append("mesh volume is not positive")
        }
        if mesh.mmPerPixel < nozzleMm {
            warnings.append(String(
                format: "sampling %.3f mm/px is finer than the %.2f mm nozzle; "
                      + "detail below that will not print",
                mesh.mmPerPixel, nozzleMm))
        }
        return warnings
    }
}
