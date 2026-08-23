import RealityKit
import ReliefCore
import UIKit

/// The floor the relief stands on: a reference plane ruled in the model's own
/// millimetres.
///
/// Orbiting a lone object against an empty background reads as the object
/// tumbling rather than the camera moving — nothing in frame stays put to turn
/// against. A ground plane fixes that. Ruling it at a round millimetre spacing
/// makes it a ruler as well: the readout can say the plate is 148 mm wide, but
/// only the grid shows what 10 mm looks like across the relief.
enum ReliefGrid {

    /// The built grid, plus the spacing it settled on so the readout can name
    /// it. A grid whose scale the user has to guess at is just decoration.
    struct Result {
        var entity: Entity
        var spacingMm: Double
    }

    /// Spacing candidates, in millimetres. Round numbers only — a 7 mm cell is
    /// no use as a ruler even where it happens to divide the plate evenly.
    private static let steps: [Double] = [1, 2, 5, 10, 20, 25, 50, 100, 200, 500]

    /// At most this many cells across the plate. Past roughly twenty the lines
    /// close up into a grey wash at any zoom the framing actually uses.
    private static let cellsAcrossPlate: Double = 20

    /// Every fifth line is drawn heavier, which is what makes the grid
    /// countable: five thin cells between two thick ones can be read at a
    /// glance where twenty identical ones cannot.
    private static let majorEvery = 5

    /// How far the floor reaches, as a multiple of the plate's footprint.
    private static let reach: Float = 1.45

    /// Brightness bands, as fractions of the grid's radius. Three concentric
    /// bands rather than a fade shader: a hard-edged disc of lines announces
    /// itself as a prop, and stepping the bands costs six materials and nothing
    /// at draw time.
    private static let bands: [Float] = [0.45, 0.75, 1.0]

    /// Opacity per band, minor lines then major.
    private static let minorAlpha: [Float] = [0.17, 0.085, 0.032]
    private static let majorAlpha: [Float] = [0.40, 0.19, 0.075]

    /// Line width per band, as a fraction of the widths below.
    ///
    /// Opacity alone cannot carry the fade. Measured against the canvas, the
    /// rim at an opacity of 0.03 still came back at 121 where the middle at
    /// 0.60 was 164 — barely a third of the way down, because the response
    /// compresses hard at the bottom of the range. Width is geometry rather
    /// than shading, so it fades exactly as asked, and the two together get
    /// the rim down to where it belongs.
    private static let bandWidth: [Float] = [1.0, 0.72, 0.45]

    /// Base line widths, in scene units. The scene is always `sceneSize`
    /// across, so constants here hold for every plate.
    private static let minorWidth: Float = 0.00055
    private static let majorWidth: Float = 0.00105

    /// Well below white. The floor is lit, and a white one renders bright
    /// enough to compete with the relief no matter what the opacity says.
    private static let lineTint = UIColor(white: 0.50, alpha: 1)

    // MARK: - Building

    static func build(for mesh: ReliefPreviewMesh) async -> Result? {
        guard mesh.widthMm > 0, mesh.extent.x > 0 else { return nil }

        // The mesh arrives already normalised into scene units; recovering the
        // factor from the plate's own width is what keeps the grid honest —
        // a 10 mm cell here is 10 mm on the printed part, whatever the plate.
        let unitsPerMm = mesh.extent.x / Float(mesh.widthMm)
        let spacingMm = steps.first { mesh.widthMm / $0 <= cellsAcrossPlate } ?? steps[steps.count - 1]
        let spacing = Float(spacingMm) * unitsPerMm
        guard spacing > 0, spacing.isFinite else { return nil }

        // Whole cells out to about one and a half plate widths. Snapping the
        // radius to the spacing is what gives the rim its rounded scallop
        // instead of the outermost ring ending on a ragged part-cell.
        let footprint = max(mesh.extent.x, mesh.extent.z) * reach
        let lines = min(max(Int((footprint / spacing).rounded()), 2), 256)
        let outer = Float(lines) * spacing

        var parts = [Ribbons](repeating: Ribbons(), count: bands.count * 2)
        for step in -lines...lines {
            let offset = Float(step) * spacing
            let isMajor = step % majorEvery == 0
            let base = isMajor ? majorWidth : minorWidth

            for span in spans(offset: offset, outer: outer) {
                let slot = span.band * 2 + (isMajor ? 1 : 0)
                let width = base * bandWidth[span.band]
                // Both halves of the line, and both axes: the bands are
                // circles, so the same span mirrors four ways about the origin.
                for axis in [Axis.alongX, .alongZ] {
                    parts[slot].add(axis, offset: offset,
                                    from: span.from, to: span.to, width: width)
                    parts[slot].add(axis, offset: offset,
                                    from: -span.to, to: -span.from, width: width)
                }
            }
        }

        // A separate entity and material per band, rather than one mesh whose
        // parts index into an array of six. Both render the same, but with one
        // mesh the per-part material assignment is a step removed from the
        // geometry it applies to, and getting it wrong looks identical to the
        // opacity not working — which cost a long detour the first time round.
        let entity = Entity()
        for (slot, ribbons) in parts.enumerated() where !ribbons.isEmpty {
            let band = slot / 2
            let alpha = slot % 2 == 0 ? minorAlpha[band] : majorAlpha[band]
            guard alpha > 0, let resource = try? await MeshResource(
                from: [ribbons.descriptor(name: "grid-\(slot)")]) else { continue }

            entity.addChild(ModelEntity(mesh: resource,
                                        materials: [material(alpha: alpha)]))
        }

        guard !entity.children.isEmpty else { return nil }
        // Sat on the plate's underside so the relief stands on the floor rather
        // than hovering over it, dropped a hair further to keep the two
        // coplanar surfaces from fighting over the bottom face.
        entity.position.y = -mesh.extent.y / 2 - 0.0002
        return Result(entity: entity, spacingMm: spacingMm)
    }

    /// Where each brightness band starts and ends along a line sitting `offset`
    /// from the centre, on the positive side only — the caller mirrors it.
    ///
    /// The bands are circles, so how much of a line falls in each depends on
    /// how close to the middle it runs: a line through the origin crosses all
    /// three, one near the rim only ever reaches the faintest.
    private static func spans(offset: Float,
                              outer: Float) -> [(band: Int, from: Float, to: Float)] {
        var result: [(band: Int, from: Float, to: Float)] = []
        var previous: Float = 0
        for (band, fraction) in bands.enumerated() {
            let radius = fraction * outer
            let along = (radius * radius - offset * offset).squareRoot()
            // NaN once the band's circle no longer reaches this line at all.
            guard along.isFinite, along > previous else { continue }
            result.append((band, previous, along))
            previous = along
        }
        return result
    }

    /// `PhysicallyBasedMaterial` rather than the `UnlitMaterial` these ruled
    /// lines otherwise want: on `UnlitMaterial` blending is compiled into the
    /// material's *program*, and without one neither `blending` nor an alpha
    /// on the tint has any effect at all — measured, every band rendered the
    /// same flat white. Blending matters more here than being unlit.
    ///
    /// Being lit costs little anyway. A directional light falls evenly across
    /// a horizontal plane, so the three in the rig shade the floor uniformly
    /// even though the key rakes hard across the relief standing on it.
    /// Specular is off for the same reason — and because opacity does not
    /// scale it, so with it on the faintest band could not fade below a flat
    /// grey no matter how low its alpha went.
    private static func material(alpha: Float) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: lineTint)
        material.roughness = 1.0
        material.metallic = 0.0
        material.specular = 0.0
        material.blending = .transparent(opacity: .init(scale: alpha))
        // Orbit lets the camera get under the floor, and a grid that vanishes
        // from below looks like a bug.
        material.faceCulling = .none
        return material
    }

    // MARK: - Geometry

    private enum Axis {
        case alongX, alongZ
    }

    /// Flat quads in the XZ plane. RealityKit's `MeshDescriptor` has no line
    /// primitive, so every rule is a ribbon two triangles wide; the width is in
    /// world units, which is also what keeps the lines from thinning to nothing
    /// when the user pinches out.
    private struct Ribbons {
        private var positions: [SIMD3<Float>] = []
        private var normals: [SIMD3<Float>] = []
        private var indices: [UInt32] = []

        var isEmpty: Bool { indices.isEmpty }

        mutating func add(_ axis: Axis, offset: Float,
                          from start: Float, to end: Float, width: Float) {
            guard end - start > .ulpOfOne else { return }
            let half = width / 2
            switch axis {
            case .alongX:
                quad(minX: start, maxX: end, minZ: offset - half, maxZ: offset + half)
            case .alongZ:
                quad(minX: offset - half, maxX: offset + half, minZ: start, maxZ: end)
            }
        }

        /// Wound so the normal points up: `(minX, minZ) → (minX, maxZ) →
        /// (maxX, maxZ)` crosses to +Y in a right-handed frame.
        private mutating func quad(minX: Float, maxX: Float, minZ: Float, maxZ: Float) {
            let base = UInt32(positions.count)
            positions.append(contentsOf: [
                SIMD3(minX, 0, minZ), SIMD3(minX, 0, maxZ),
                SIMD3(maxX, 0, maxZ), SIMD3(maxX, 0, minZ),
            ])
            normals.append(contentsOf: repeatElement(SIMD3(0, 1, 0), count: 4))
            indices.append(contentsOf: [base, base + 1, base + 2,
                                        base, base + 2, base + 3])
        }

        func descriptor(name: String) -> MeshDescriptor {
            var descriptor = MeshDescriptor(name: name)
            descriptor.positions = MeshBuffers.Positions(positions)
            descriptor.normals = MeshBuffers.Normals(normals)
            descriptor.primitives = .triangles(indices)
            return descriptor
        }
    }
}
