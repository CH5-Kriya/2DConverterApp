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
    @AppStorage("relief3DShowsStatistics") private var showsStatistics = true
    @AppStorage("relief3DShowsWireframe") private var showsWireframe = false
    @AppStorage("relief3DAutoRotate") private var autoRotate = false
    @AppStorage("relief3DCameraZoom") private var cameraZoom = 1.0
    @AppStorage("relief3DLaysFlatOnGrid") private var laysFlatOnGrid = false

    @State private var isShowingDisplaySettings = false

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
            .onChange(of: cameraZoom, initial: true) { _, zoom in
                stage.setZoom(1 / Float(zoom))
            }
            .onChange(of: laysFlatOnGrid, initial: true) { _, liesFlat in
                stage.setLiesFlatOnGrid(liesFlat)
            }
            .task(id: WireframeRequest(meshID: mesh?.id, isEnabled: showsWireframe)) {
                await stage.setShowsWireframe(showsWireframe, for: mesh)
            }
            .task(id: autoRotate) {
                await stage.runAutoRotation(enabled: autoRotate)
            }
            .gesture(orbit)
            .simultaneousGesture(dolly)
        }
        .overlay(alignment: .topLeading) { readout }
        .overlay(alignment: .topLeading) { displayControls }
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
                let cameraDistance = stage.dolly(
                    by: Float(value.magnification / lastMagnification))
                cameraZoom = Double(1 / cameraDistance)
                lastMagnification = value.magnification
            }
            .onEnded { _ in isZooming = false }
    }

    @ViewBuilder
    private var readout: some View {
        if showsStatistics, let mesh {
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
    private var displayControls: some View {
        if mesh != nil {
            HStack(alignment: .top, spacing: 10) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isShowingDisplaySettings.toggle()
                    }
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 18, weight: .medium))
                }
                .foregroundStyle(Theme.Palette.workspaceLabel)
                .accessibilityLabel("Display settings")
                .accessibilityValue(isShowingDisplaySettings ? "Expanded" : "Collapsed")
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .tint(Theme.Palette.workspaceControl)

                if isShowingDisplaySettings {
                    DisplaySettingsPanel(
                        showsGrid: $showsGrid,
                        showsStatistics: $showsStatistics,
                        showsWireframe: $showsWireframe,
                        autoRotate: $autoRotate,
                        cameraZoom: $cameraZoom,
                        laysFlatOnGrid: $laysFlatOnGrid
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.96,
                                                                anchor: .leading)))
                }
            }
            // The readout already owns the upper-left corner. Display controls
            // live directly below it when it is visible, but stay in the same
            // left-hand position if Statistics is turned off.
            .padding(.leading, 16)
            .padding(.top, showsStatistics ? 64 : 16)
        }
    }

    private static let count: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()
}

private struct DisplaySettingsPanel: View {
    @Binding var showsGrid: Bool
    @Binding var showsStatistics: Bool
    @Binding var showsWireframe: Bool
    @Binding var autoRotate: Bool
    @Binding var cameraZoom: Double
    @Binding var laysFlatOnGrid: Bool

    private static let defaultZoom = 1.0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Display Settings")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.Palette.textPrimary)
                .padding(.bottom, 16)

            settingToggle("Grid", isOn: $showsGrid)
            settingToggle("Statistics", isOn: $showsStatistics)
            settingToggle("Wireframe", isOn: $showsWireframe)
            settingToggle("Auto-rotate", isOn: $autoRotate)
            settingToggle("Lay Flat on Grid", isOn: $laysFlatOnGrid)

            HStack {
                Text("Camera Zoom")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.Palette.textPrimary)
                Spacer()
                Text("\(Int(cameraZoom * 100))%")
                    .font(.system(size: 16).monospacedDigit())
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            .padding(.top, 12)

            HStack(spacing: 12) {
                Slider(value: $cameraZoom, in: 0.3...4.0, step: 0.05)
                    .tint(Theme.Palette.textPrimary)

                Button {
                    cameraZoom = Self.defaultZoom
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 16, weight: .medium))
                        .frame(width: 38, height: 38)
                }
                .foregroundStyle(Theme.Palette.textSecondary)
                .background(Theme.Palette.workspaceControl,
                            in: RoundedRectangle(cornerRadius: 10,
                                                 style: .continuous))
                .accessibilityLabel("Reset camera zoom")
            }
            .padding(.top, 6)
        }
        .padding(24)
        .frame(width: Theme.Metrics.workspacePanelWidth, alignment: .leading)
        .background(Theme.Palette.workspacePanel.opacity(0.78),
                    in: RoundedRectangle(cornerRadius: Theme.Metrics.workspacePanelRadius,
                                         style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Metrics.workspacePanelRadius,
                             style: .continuous)
                .strokeBorder(Theme.Palette.workspaceStroke.opacity(0.16), lineWidth: 0.5)
        )
    }

    private func settingToggle(_ title: String,
                               isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title)
                .font(.system(size: 14))
                .foregroundStyle(Theme.Palette.textPrimary)
        }
        .tint(Theme.Palette.textPrimary)
        .padding(.vertical, 5)
    }
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

/// The wireframe construction has to re-run when either the source geometry
/// or its visibility changes. A named value keeps that dependency explicit to
/// SwiftUI's task system.
private struct WireframeRequest: Equatable {
    var meshID: UUID?
    var isEnabled: Bool
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
    /// A child of the model, so it follows every standing/flat and turntable
    /// transformation exactly instead of maintaining a second pose.
    private let wireframe = Entity()

    /// Cell size of the floor currently under the model, in millimetres.
    private(set) var gridSpacingMm: Double?

    var showsGrid = true {
        didSet { floor.isEnabled = showsGrid }
    }

    private let camera = PerspectiveCamera()
    private let material: PhysicallyBasedMaterial
    private var loaded: UUID?
    private var wireframeLoaded: UUID?

    /// The camera pose, in spherical coordinates about the origin: the arm
    /// length that fits the plate to the viewport, the user's zoom riding on
    /// top of it, and where they have turned the model to.
    private var fitted: Float = 0.4
    private var zoom: Float = 1
    private var yaw = ReliefStage.homeYaw
    private var pitch = ReliefStage.homePitch
    private var modelRoll: Float = 0
    private var liesFlatOnGrid = false
    private var meshExtent: SIMD3<Float>?

    /// Straight-on with a little lift and offset: enough perspective to read
    /// the depth, close enough to head-on that the image is still legible.
    private static let homeDirection = simd_normalize(SIMD3<Float>(0.09, 0.10, 0.40))
    private static let homeYaw = atan2(homeDirection.x, homeDirection.z)
    private static let homePitch = asin(homeDirection.y)
    private static let defaultFieldOfView: Float = 50

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

        camera.camera.fieldOfViewInDegrees = Self.defaultFieldOfView
        aim()

        root.addChild(model)
        model.addChild(wireframe)
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
        meshExtent = snapshot.extent
        updateModelOrientation()
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
        positionFloor()
    }

    /// Stands the camera back far enough that the plate fits the viewport.
    ///
    /// A fixed distance cannot work: the field of view is vertical, so the same
    /// camera that frames the relief in a wide workspace crops it badly in a
    /// narrow one. Both axes are checked and the further of the two wins.
    func frame(_ framing: Framing) {
        guard let extent = framing.extent, framing.aspect > 0,
              framing.aspect.isFinite else { return }

        let halfFov = Self.defaultFieldOfView / 2 * .pi / 180
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
    @discardableResult
    func dolly(by step: Float) -> Float {
        guard step > 0, step.isFinite else { return zoom }
        // Pinching out enlarges the model, which is a *shorter* camera arm —
        // hence the divide. Raising each incremental step to the exponent
        // compounds to exactly the same damping as raising the gesture's total
        // would, so how finely SwiftUI slices the pinch up does not matter.
        zoom = min(max(zoom / pow(step, Self.zoomResponse), Self.zoomNearest),
                   Self.zoomFurthest)
        aim()
        return zoom
    }

    func setZoom(_ value: Float) {
        guard value.isFinite else { return }
        zoom = min(max(value, Self.zoomNearest), Self.zoomFurthest)
        aim()
    }

    /// Turns the upright relief into a plate resting on the XZ floor. The
    /// relief is authored in XY with depth along +Z, so -90° around X puts its
    /// face upward (+Y) without mirroring the image.
    func setLiesFlatOnGrid(_ value: Bool) {
        liesFlatOnGrid = value
        updateModelOrientation()
        positionFloor()
    }

    /// Shows a sampled rendering of the regular top-surface triangulation.
    /// The export may contain millions of edges, so drawing every edge would
    /// make this display aid less useful than the model itself. Sampling still
    /// preserves the actual triangle direction and density pattern while
    /// keeping interaction smooth.
    func setShowsWireframe(_ value: Bool, for snapshot: ReliefPreviewMesh?) async {
        wireframe.isEnabled = value
        guard value, let snapshot else { return }
        guard snapshot.id != wireframeLoaded else { return }

        guard let descriptor = ReliefWireframe.descriptor(for: snapshot),
              let resource = try? await MeshResource(from: [descriptor]),
              !Task.isCancelled,
              wireframe.isEnabled else { return }

        wireframe.children.removeAll()
        wireframe.addChild(ModelEntity(mesh: resource, materials: [Self.wireMaterial]))
        wireframeLoaded = snapshot.id
    }

    func runAutoRotation(enabled: Bool) async {
        guard enabled else { return }

        let clock = ContinuousClock()
        while !Task.isCancelled {
            let start = clock.now
            modelRoll += 0.012
            updateModelOrientation()
            let elapsed = clock.now - start
            do {
                let remaining = .milliseconds(30) - elapsed
                if remaining > .zero {
                    try await clock.sleep(for: remaining)
                }
            } catch {
                return
            }
        }
    }

    /// Applies the standing/lying pose first, then rotates it around the
    /// world's vertical axis so an auto-rotating flat relief still turns like
    /// an object placed on a table.
    private func updateModelOrientation() {
        let base = liesFlatOnGrid
            ? simd_quatf(angle: -.pi / 2, axis: SIMD3<Float>(1, 0, 0))
            : simd_quatf(angle: 0, axis: SIMD3<Float>(1, 0, 0))
        let turntable = simd_quatf(angle: modelRoll, axis: SIMD3<Float>(0, 1, 0))
        model.orientation = turntable * base
    }

    /// `ReliefGrid` is built for an upright plate, whose lower edge is
    /// `extent.y / 2` below its origin. A lying plate's thickness is its Z
    /// extent, so its floor moves up to meet that thinner underside instead.
    private func positionFloor() {
        guard let extent = meshExtent else { return }
        floor.position.y = liesFlatOnGrid ? (extent.y - extent.z) / 2 : 0
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

    private static let wireMaterial: PhysicallyBasedMaterial = {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: UIColor(white: 0.06, alpha: 1))
        material.roughness = 1.0
        material.metallic = 0.0
        material.faceCulling = .none
        return material
    }()
}

/// RealityKit's public custom-mesh API has triangles but no line primitive.
/// Each line below is therefore a very narrow, two-sided ribbon lifted just
/// clear of the relief surface. Crucially, the source is `indices`, rather
/// than an assumed image grid, so this follows the actual face topology —
/// including any future decimation and the sides/back of the printable solid.
private enum ReliefWireframe {
    /// Fully expanded wire ribbons are four new vertices per edge. Showing
    /// every edge of a 900 × 900 preview would be millions of ribbons and can
    /// exhaust an iPad's GPU memory, so exceptionally dense previews sample
    /// their *real* triangles evenly across the index buffer. Normal meshes
    /// (up to this face count) show every edge exactly.
    private static let maximumFaces = 200_000
    private static let lineWidth: Float = 0.00024
    private static let surfaceLift: Float = 0.00012

    static func descriptor(for snapshot: ReliefPreviewMesh) -> MeshDescriptor? {
        let faceCount = snapshot.indices.count / 3
        guard faceCount > 0 else {
            return nil
        }

        let displayedFaces = min(faceCount, maximumFaces)
        var edges = Set<WireframeEdge>()
        edges.reserveCapacity(displayedFaces * 2)
        for sample in 0..<displayedFaces {
            // This distributes a capped selection over the entire mesh rather
            // than drawing only the first part of its index buffer.
            let face = sample * faceCount / displayedFaces
            let base = face * 3
            let a = snapshot.indices[base]
            let b = snapshot.indices[base + 1]
            let c = snapshot.indices[base + 2]
            edges.insert(WireframeEdge(a, b))
            edges.insert(WireframeEdge(b, c))
            edges.insert(WireframeEdge(c, a))
        }

        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        positions.reserveCapacity(edges.count * 4)
        normals.reserveCapacity(edges.count * 4)
        indices.reserveCapacity(edges.count * 6)

        func addRibbon(from first: Int, to second: Int) {
            let start = snapshot.positions[first]
            let end = snapshot.positions[second]
            let length = simd_length(end - start)
            guard length > .ulpOfOne else { return }

            let direction = (end - start) / length
            var normal = snapshot.normals[first] + snapshot.normals[second]
            let normalLength = simd_length(normal)
            normal = normalLength > .ulpOfOne
                ? normal / normalLength
                : SIMD3<Float>(0, 0, 1)

            var side = simd_cross(direction, normal)
            let sideLength = simd_length(side)
            guard sideLength > .ulpOfOne else { return }
            side = side / sideLength * (lineWidth / 2)

            let lift = normal * surfaceLift
            let base = UInt32(positions.count)
            positions += [start + lift - side, start + lift + side,
                          end + lift + side, end + lift - side]
            normals += [normal, normal, normal, normal]
            indices += [base, base + 1, base + 2, base, base + 2, base + 3]
        }

        for edge in edges {
            addRibbon(from: Int(edge.lower), to: Int(edge.upper))
        }

        guard !positions.isEmpty else { return nil }
        var descriptor = MeshDescriptor(name: "relief wireframe")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.primitives = .triangles(indices)
        return descriptor
    }

}

/// An undirected mesh edge. Triangles commonly share an edge, but it is drawn
/// once in the wireframe rather than twice as a darker, thicker ribbon.
private struct WireframeEdge: Hashable {
    let lower: UInt32
    let upper: UInt32

    init(_ first: UInt32, _ second: UInt32) {
        lower = min(first, second)
        upper = max(first, second)
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
