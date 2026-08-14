import RealityKit
import ReliefCore
import SwiftUI
import UIKit

/// The relief as a solid the user can turn over in their hands, which is the
/// only way some of these parameters can be judged: smoothness and texture
/// change the surface at grazing angles long before they change it head-on.
///
/// `RealityView` plus `.realityViewCameraControls(.orbit)` is what gives the
/// STL-viewer interaction — drag to orbit, pinch to dolly — without hand-rolling
/// the gesture stack. RealityKit rather than SceneKit because SceneKit is
/// deprecated.
struct Relief3DPreview: View {
    var mesh: ReliefPreviewMesh?

    @State private var stage = ReliefStage()

    var body: some View {
        GeometryReader { proxy in
            RealityView { content in
                content.camera = .virtual
                content.environment = .default
                content.add(stage.root)
                // No `cameraTarget`: it frames the camera against the target's
                // bounds at setup, and the mesh does not exist yet at that
                // point, so it would park the camera inside the model. The mesh
                // is normalised around the origin instead, which is what orbit
                // falls back to pivoting on.
            }
            .realityViewCameraControls(.orbit)
            // Re-created only on the initial fit and on an explicit Reset: the
            // orbit controller owns its pose internally, so a fresh view is the
            // reliable way to make a new one stick. Deliberately *not* on every
            // resize — see `frame(_:)` for what that costs.
            .id(stage.generation)
            .task(id: mesh?.id) { await stage.show(mesh) }
            .onChange(of: Framing(size: proxy.size, extent: mesh?.extent),
                      initial: true) { _, framing in
                stage.frame(framing)
            }
        }
        .overlay(alignment: .topLeading) { readout }
        .overlay(alignment: .topTrailing) { resetButton }
        .accessibilityLabel("3D preview")
        .accessibilityHint("Drag to orbit the model, pinch to zoom.")
    }

    @ViewBuilder
    private var readout: some View {
        if let mesh {
            Text(String(format: "%.0f × %.0f × %.1f mm · %@ triangles",
                        mesh.widthMm, mesh.heightMm, mesh.thicknessMm,
                        Self.count.string(from: mesh.triangleCount as NSNumber) ?? "—"))
                .font(.system(size: 12, weight: .regular))
                .monospacedDigit()
                .foregroundStyle(Theme.Palette.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Theme.Palette.workspaceControl.opacity(0.72),
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .padding(16)
        }
    }

    @ViewBuilder
    private var resetButton: some View {
        if mesh != nil {
            Button {
                stage.resetView()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 15, weight: .medium))
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .tint(Theme.Palette.workspaceControl)
            .foregroundStyle(Theme.Palette.workspaceLabel)
            .padding(16)
            .accessibilityLabel("Reset view")
        }
    }

    private static let count: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()
}

/// Everything the camera distance depends on. Bundled so one `onChange` covers
/// both a rotation and a mesh whose plate has a different aspect than the last.
struct Framing: Equatable {
    var size: CGSize
    var extent: SIMD3<Float>?

    var aspect: Float {
        size.height > 0 ? Float(size.width / size.height) : 1
    }
}

// MARK: - Scene

/// Owns the entities across view rebuilds. Keeping them here rather than
/// building them inside `RealityView`'s make closure is what lets a new mesh
/// swap in without the camera jumping back to its starting pose mid-edit.
@Observable
final class ReliefStage {

    let root = Entity()
    let model = ModelEntity()

    /// Bumped to force `RealityView` to be re-created; see `resetView()`.
    private(set) var generation = 0

    private let camera = PerspectiveCamera()
    private let material: PhysicallyBasedMaterial
    private var loaded: UUID?
    /// Whether the camera has been fitted to the model once.
    private var hasFramed = false
    private var distance: Float = 0.4

    /// Straight-on with a little lift and offset: enough perspective to read
    /// the depth, close enough to head-on that the image is still legible.
    private static let homeDirection = simd_normalize(SIMD3<Float>(0.09, 0.10, 0.40))
    private static let fieldOfView: Float = 50

    init() {
        var surface = PhysicallyBasedMaterial()
        // Unpigmented filament, roughly. Kept well below white: at 0.86 the lit
        // side clipped and the shading range collapsed, which is most of what
        // made the surface read as flat shaded plastic.
        surface.baseColor = .init(tint: UIColor(red: 0.70, green: 0.68, blue: 0.64, alpha: 1))
        // Enough gloss for a specular roll across the relief. Fully matte hides
        // exactly the micro-slope changes the Texture slider is moving.
        surface.roughness = 0.55
        surface.metallic = 0.0
        // `relief_solidify` + `relief_fix_normals` give a closed, outward-wound
        // solid — asserted watertight in `PreviewMeshTests` — so back faces are
        // genuinely hidden and culling them is both correct and cheaper.
        surface.faceCulling = .back
        material = surface

        camera.camera.fieldOfViewInDegrees = Self.fieldOfView
        camera.look(at: .zero, from: Self.homeDirection * distance, relativeTo: nil)

        root.addChild(model)
        root.addChild(camera)
        addLights()
    }

    func show(_ snapshot: ReliefPreviewMesh?) async {
        // The entities outlive the view, so a view rebuild — a reframe, a reset —
        // finds the mesh already on the model and can skip regenerating it.
        guard let snapshot, snapshot.id != loaded else { return }

        var descriptor = MeshDescriptor(name: "relief")
        descriptor.positions = MeshBuffers.Positions(snapshot.positions)
        descriptor.normals = MeshBuffers.Normals(snapshot.normals)
        descriptor.primitives = .triangles(snapshot.indices)

        guard let resource = try? await MeshResource(from: [descriptor]),
              !Task.isCancelled else { return }
        model.model = ModelComponent(mesh: resource, materials: [material])
        loaded = snapshot.id
    }

    /// Stands the camera back far enough that the plate fits the viewport.
    ///
    /// A fixed distance cannot work: the field of view is vertical, so the same
    /// camera that frames the relief in a wide workspace crops it badly in a
    /// narrow one. Both axes are checked and the further of the two wins.
    func frame(_ framing: Framing) {
        guard let extent = framing.extent, framing.aspect > 0,
              framing.aspect.isFinite else { return }

        let halfFov = Self.fieldOfView / 2 * .pi / 180
        let vertical = (extent.y / 2) / tan(halfFov)
        let horizontal = (extent.x / 2) / tan(atan(tan(halfFov) * framing.aspect))
        // A little air around the plate, plus the relief itself, which stands
        // off the back plate toward the camera.
        let wanted = max(vertical, horizontal) * 1.25 + extent.z / 2

        guard abs(wanted - distance) > 0.001 else { return }
        distance = wanted
        aim()

        // Only the *first* framing may re-create the view.
        //
        // `proxy.size` changes on every frame of a resize animation — collapsing
        // the sidebar is 0.28 s, so roughly seventeen of them — and re-creating
        // the RealityView each time stands up seventeen CAMetalLayers before the
        // first is released. The drawable pool runs dry and Metal starts
        // answering `nextDrawable` with nil. After the initial fit the camera
        // simply moves; the view stays where it is.
        if !hasFramed {
            hasFramed = true
            generation += 1
        }
    }

    /// Puts the camera back where it started. The orbit controller keeps its
    /// own pose, so restoring the entity transform is only half of it — the
    /// view has to be re-created for the controller to pick the pose back up.
    ///
    /// This is the one gesture that earns a rebuild, because it is the one the
    /// person explicitly asked for.
    func resetView() {
        aim()
        generation += 1
    }

    /// Moves the camera. Nothing else.
    private func aim() {
        camera.look(at: .zero, from: Self.homeDirection * distance, relativeTo: nil)
    }

    /// A three-point rig with the key deliberately raking across the surface.
    /// Relief legibility is judged by the shadows it throws, so a light aimed
    /// down the camera axis — the obvious choice — is the wrong one: it washes
    /// out exactly the depth cues the user is here to tune.
    private func addLights() {
        func light(_ position: SIMD3<Float>, intensity: Float, colour: UIColor,
                   castsShadow: Bool = false) {
            let entity = DirectionalLight()
            entity.light = DirectionalLightComponent(color: colour, intensity: intensity)
            if castsShadow {
                var shadow = DirectionalLightComponent.Shadow()
                // The default projection spans 5 m. This model is 0.3 m across,
                // so that would spend the whole shadow map on empty space and
                // return mush. Fitted to the mesh instead.
                shadow.shadowProjection = .fixed(zNear: 0.01, zFar: 2,
                                                 orthographicScale: 0.45)
                entity.shadow = shadow
            }
            entity.look(at: .zero, from: position, relativeTo: nil)
            root.addChild(entity)
        }

        // The key rakes across the surface and casts: relief is legible through
        // the shadows it throws, and without a shadow map the crevices get the
        // same light as the peaks, which is the flat clay look.
        light(SIMD3(-0.55, 0.50, 0.30), intensity: 2200,
              colour: UIColor(red: 1.0, green: 0.98, blue: 0.94, alpha: 1),
              castsShadow: true)
        // Fill and rim stay dim and shadowless — they exist to keep the dark
        // side from going to black, not to add a second set of shadows.
        light(SIMD3(0.60, -0.20, 0.55), intensity: 500,
              colour: UIColor(red: 0.90, green: 0.94, blue: 1.0, alpha: 1))
        light(SIMD3(0.10, 0.35, -0.70), intensity: 800, colour: .white)
    }
}

/// A synthetic relief, so the viewer can be worked on without waiting for a
/// conversion — the real pipeline takes minutes and needs a photo.
#Preview(traits: .landscapeLeft) {
    let rows = 160, cols = 200
    var values = [Float](repeating: 0, count: rows * cols)
    for r in 0..<rows {
        for c in 0..<cols {
            let u = Float(c) / Float(cols - 1) - 0.5
            let v = Float(r) / Float(rows - 1) - 0.5
            values[r * cols + c] = max(0, 0.22 - (u * u + v * v)) * 3
                + 0.05 * sin(26 * u) * cos(20 * v)
        }
    }

    var config = MeshConfig()
    config.reliefMm = 30

    return Relief3DPreview(mesh: ReliefPreviewMeshBuilder.build(
        height: Plane(rows: rows, cols: cols, values: values), config: config))
        .background(Theme.Palette.workspaceCanvas)
        .preferredColorScheme(.dark)
}
