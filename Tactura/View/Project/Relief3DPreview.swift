import RealityKit
import ReliefCore
import SwiftUI
import UIKit

/// The relief as a solid the user can turn over in their hands, which is the
/// only way some of these parameters can be judged: smoothness and texture
/// change the surface at grazing angles long before they change it head-on.
///
/// STL-viewer interaction — drag to orbit, pinch to dolly — with the camera
/// driven from `ReliefStage` rather than by `.realityViewCameraControls(.orbit)`.
/// The built-in controller is the obvious choice and was the first one, but its
/// pinch gain is fixed and far too eager at this scale: a plate is 0.3 m across,
/// and a modest pinch dollied the camera clean through it. `CameraControls`
/// exposes no way to turn that down, so the gesture stack is ours.
/// RealityKit rather than SceneKit because SceneKit is deprecated.
struct Relief3DPreview: View {
    var mesh: ReliefPreviewMesh?

    @State private var stage = ReliefStage()

    /// Sticky rather than per-visit: whether the floor helps or gets in the way
    /// is a standing preference about how someone reads a relief, not a
    /// decision they want to retake every time they open a project.
    @AppStorage("relief3DShowsGrid") private var showsGrid = true

    /// Both gestures report totals measured from where they began, and the
    /// camera moves in increments, so the last reading has to be kept to
    /// difference against.
    @State private var lastTranslation: CGSize = .zero
    @State private var lastMagnification: CGFloat = 1

    /// A pinch drifts its centroid as the fingers move, and SwiftUI hands that
    /// drift to the drag gesture as well — which spun the model while the user
    /// was only trying to zoom. The drag stands down for the duration.
    @State private var isZooming = false

    var body: some View {
        GeometryReader { proxy in
            RealityView { content in
                content.camera = .virtual
                content.environment = .default
                content.add(stage.root)
                // No `cameraTarget`: it frames the camera against the target's
                // bounds at setup, and the mesh does not exist yet at that
                // point, so it would park the camera inside the model. The mesh
                // is normalised around the origin instead, which is what the
                // camera pivots on.
            }
            // See the type's note: `.orbit` zooms far too hard for a plate this
            // size and offers no gain to lower, so the camera is posed by hand.
            .realityViewCameraControls(.none)
            .task(id: mesh?.id) { await stage.show(mesh) }
            .onChange(of: Framing(size: proxy.size, extent: mesh?.extent),
                      initial: true) { _, framing in
                stage.frame(framing)
            }
            .onChange(of: showsGrid, initial: true) { _, shows in
                stage.showsGrid = shows
            }
            .gesture(orbit)
            .simultaneousGesture(dolly)
        }
        .overlay(alignment: .topLeading) { readout }
        .overlay(alignment: .topTrailing) { controls }
        .accessibilityLabel("3D preview")
        .accessibilityHint("Drag to orbit the model, pinch to zoom.")
    }

    private var orbit: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                defer { lastTranslation = value.translation }
                guard !isZooming else { return }
                stage.orbit(dx: Float(value.translation.width - lastTranslation.width),
                            dy: Float(value.translation.height - lastTranslation.height))
            }
            .onEnded { _ in lastTranslation = .zero }
    }

    private var dolly: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                // A pinch that is cancelled rather than ended leaves the last
                // reading stale, so the opening change of a new one seeds it
                // rather than differencing against it.
                guard isZooming else {
                    isZooming = true
                    lastMagnification = value.magnification
                    return
                }
                stage.dolly(by: Float(value.magnification / lastMagnification))
                lastMagnification = value.magnification
            }
            .onEnded { _ in isZooming = false }
    }

    @ViewBuilder
    private var readout: some View {
        if let mesh {
            Text(caption(for: mesh))
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

    /// The grid's cell size belongs here rather than on the grid itself: a
    /// floating label in the scene would have to fight the model for space and
    /// track the camera, and the readout is already where sizes are stated.
    private func caption(for mesh: ReliefPreviewMesh) -> String {
        var text = String(format: "%.0f × %.0f × %.1f mm · %@ triangles",
                          mesh.widthMm, mesh.heightMm, mesh.thicknessMm,
                          Self.count.string(from: mesh.triangleCount as NSNumber) ?? "—")
        if showsGrid, let spacing = stage.gridSpacingMm {
            text += String(format: " · %g mm grid", spacing)
        }
        return text
    }

    @ViewBuilder
    private var controls: some View {
        if mesh != nil {
            Button {
                showsGrid.toggle()
            } label: {
                // The circle is drawn around the glyph, so the glyph's size is
                // what sizes the button.
                Image(systemName: "square.grid.3x3")
                    .font(.system(size: 18, weight: .medium))
            }
            .foregroundStyle(showsGrid ? Theme.Palette.workspaceLabel
                                       : Theme.Palette.textTertiary)
            .accessibilityLabel("Grid")
            .accessibilityValue(showsGrid ? "On" : "Off")
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .tint(Theme.Palette.workspaceControl)
            .padding(16)
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

    /// A container rather than the grid itself, so hiding the floor and
    /// swapping it for a new plate's are independent of each other.
    private let floor = Entity()

    /// Cell size of the floor currently under the model, in millimetres.
    private(set) var gridSpacingMm: Double?

    var showsGrid = true {
        didSet { floor.isEnabled = showsGrid }
    }

    private let camera = PerspectiveCamera()
    private let material: PhysicallyBasedMaterial
    private var loaded: UUID?

    /// The camera pose, in spherical coordinates about the origin: the arm
    /// length that fits the plate to the viewport, the user's zoom riding on
    /// top of it, and where they have turned the model to.
    private var fitted: Float = 0.4
    private var zoom: Float = 1
    private var yaw = ReliefStage.homeYaw
    private var pitch = ReliefStage.homePitch

    /// Straight-on with a little lift and offset: enough perspective to read
    /// the depth, close enough to head-on that the image is still legible.
    private static let homeDirection = simd_normalize(SIMD3<Float>(0.09, 0.10, 0.40))
    private static let homeYaw = atan2(homeDirection.x, homeDirection.z)
    private static let homePitch = asin(homeDirection.y)
    private static let fieldOfView: Float = 50

    /// Pinch damping: the camera arm scales by `magnification ^ zoomResponse`.
    /// At 1.0 — roughly what the built-in orbit control does — a pinch across
    /// half the screen swallows the whole zoom range and the plate jumps from
    /// filling the viewport to a speck. Below 1 the gesture has to travel
    /// further for the same movement, which is what makes it steerable.
    private static let zoomResponse: Float = 0.45

    /// Radians of orbit per point of drag — a little over a third of a degree,
    /// so a drag across a 300 pt viewport turns the model about a half-turn.
    private static let orbitPerPoint: Float = 0.006

    /// How far either side of the fitted distance the zoom may travel. Nearer
    /// than `zoomNearest` the plate starts clipping through the near plane;
    /// past `zoomFurthest` it is too small to judge anything by.
    private static let zoomNearest: Float = 0.3
    private static let zoomFurthest: Float = 4

    /// Just short of the poles: overhead, the yaw axis collapses onto the view
    /// direction and the model spins under a sideways drag.
    private static let pitchLimit: Float = 85 * .pi / 180

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
        aim()

        root.addChild(model)
        root.addChild(floor)
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
        await layFloor(under: snapshot)
    }

    /// The floor is rebuilt with the mesh rather than made once at setup: its
    /// cell size comes from the plate's millimetre dimensions and its height
    /// from the plate's underside, so a config edit that resizes the plate has
    /// to resize the ruler beneath it too.
    private func layFloor(under snapshot: ReliefPreviewMesh) async {
        let grid = await ReliefGrid.build(for: snapshot)
        guard !Task.isCancelled else { return }

        floor.children.removeAll()
        if let grid { floor.addChild(grid.entity) }
        gridSpacingMm = grid?.spacingMm
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

        guard abs(wanted - fitted) > 0.001 else { return }
        fitted = wanted
        // The zoom multiplies the new fit rather than being cleared by it, so a
        // resize — collapsing the sidebar re-fits the plate — keeps the user
        // where they had pinched to instead of snapping back out.
        aim()
    }

    /// Turns the camera around the model.
    ///
    /// The signs are the turntable convention: the model follows the finger, so
    /// dragging right swings the camera the other way around it.
    func orbit(dx: Float, dy: Float) {
        yaw -= dx * Self.orbitPerPoint
        pitch = min(max(pitch + dy * Self.orbitPerPoint, -Self.pitchLimit),
                    Self.pitchLimit)
        aim()
    }

    /// Dollies by one step of a pinch, damped by `zoomResponse`.
    func dolly(by step: Float) {
        guard step > 0, step.isFinite else { return }
        // Pinching out enlarges the model, which is a *shorter* camera arm —
        // hence the divide. Raising each incremental step to the exponent
        // compounds to exactly the same damping as raising the gesture's total
        // would, so how finely SwiftUI slices the pinch up does not matter.
        zoom = min(max(zoom / pow(step, Self.zoomResponse), Self.zoomNearest),
                   Self.zoomFurthest)
        aim()
    }

    /// Moves the camera. Nothing else.
    private func aim() {
        let direction = SIMD3<Float>(sin(yaw) * cos(pitch),
                                     sin(pitch),
                                     cos(yaw) * cos(pitch))
        camera.look(at: .zero, from: direction * (fitted * zoom), relativeTo: nil)
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
