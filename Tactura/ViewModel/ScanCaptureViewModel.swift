import AVFoundation
import SwiftUI
import UIKit

/// Drives the scan screen: permission, the live session, one photograph, and
/// the look at it before it becomes a project.
///
/// The review step is not ceremony. Everything past this screen is on disk —
/// the import is the first checkpoint — so a shot taken at an angle or out of
/// focus would otherwise arrive in My Scans as a project someone has to go and
/// delete. Retake is cheaper than that.
@MainActor
@Observable
final class ScanCaptureViewModel {

    enum Phase: Equatable {
        case preparing
        case ready
        case review
        case denied
        /// No camera, or one that would not start. Carries what to say about it.
        case unavailable(String)
    }

    struct Capture {
        let data: Data
        let image: UIImage
    }

    private(set) var phase: Phase = .preparing
    private(set) var capture: Capture?
    private(set) var isCapturing = false

    /// Degrees, as AVFoundation counts them. Portrait until the coordinator
    /// says otherwise.
    private(set) var previewRotation: CGFloat = 90

    private var sensorAspect: CGFloat = 0

    /// The shape to give the preview, so what is on screen is exactly what the
    /// sensor will record. It matters here more than it usually does: the
    /// framing guide is drawn on the preview's corners, and on a letterboxed
    /// view those corners mark a boundary the photograph does not have.
    var previewAspect: CGFloat {
        guard sensorAspect > 0 else { return 4.0 / 3.0 }
        let isPortrait = previewRotation == 90 || previewRotation == 270
        return isPortrait ? 1 / sensorAspect : sensorAspect
    }

    var errorMessage: String?
    var hasError: Bool {
        get { errorMessage != nil }
        set { if !newValue { errorMessage = nil } }
    }

    private let engine = CameraEngine()
    private var rotation: AVCaptureDevice.RotationCoordinator?
    private var rotationObservation: NSKeyValueObservation?

    var session: AVCaptureSession { engine.session }

    // MARK: Lifecycle

    func start() async {
        // Ask the hardware before asking the person. On the simulator there is
        // no camera at all, and a permission sheet there answers a question
        // nobody can act on.
        guard let device = engine.device else {
            phase = .unavailable(
                "This device has no camera. Import your artwork from the gallery instead.")
            return
        }

        guard await requestAccess() else {
            phase = .denied
            return
        }

        do {
            try await engine.configure()
        } catch {
            phase = .unavailable(error.localizedDescription)
            return
        }

        // The screen can go away while the permission sheet is still up, and
        // `task` is cancelled with it. Nothing below is worth doing for a view
        // that has already been torn down — least of all powering the sensor.
        guard !Task.isCancelled else { return }

        sensorAspect = engine.sensorAspect
        trackRotation(of: device)
        await engine.start()
        phase = .ready
    }

    /// Coming back from the background. iOS interrupts the session on the way
    /// out and does not always hand it back running; restarting one that never
    /// stopped costs nothing.
    func resume() async {
        guard phase == .ready else { return }
        await engine.start()
    }

    func stop() async {
        rotationObservation?.invalidate()
        rotationObservation = nil
        rotation = nil
        await engine.stop()
    }

    private func requestAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:    true
        case .notDetermined: await AVCaptureDevice.requestAccess(for: .video)
        default:             false
        }
    }

    /// The coordinator tracks the *device*, not the interface, so the preview
    /// stays level whichever way the iPad is held — including the orientations
    /// SwiftUI never hears about.
    private func trackRotation(of device: AVCaptureDevice) {
        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
        rotation = coordinator
        previewRotation = coordinator.videoRotationAngleForHorizonLevelPreview

        // Two details, both deliberate. The observed object arrives as the
        // closure's argument rather than being captured, or the observation
        // would own the thing observing it; and `self` is unwrapped before the
        // hop to the main actor, because a weak capture is a mutable binding
        // and reading one from another task is an error under Swift 6.
        rotationObservation = coordinator.observe(
            \.videoRotationAngleForHorizonLevelPreview, options: [.new]
        ) { [weak self] coordinator, _ in
            let angle = coordinator.videoRotationAngleForHorizonLevelPreview
            guard let self else { return }
            Task { @MainActor in self.previewRotation = angle }
        }
    }

    // MARK: Capture

    func focus(at point: CGPoint) {
        guard phase == .ready else { return }
        engine.focus(at: point)
    }

    func takePhoto() async {
        guard phase == .ready, !isCapturing else { return }
        isCapturing = true
        defer { isCapturing = false }

        do {
            let raw = try await engine.capture(
                rotationAngle: rotation?.videoRotationAngleForHorizonLevelCapture ?? previewRotation)

            // Off the main actor: this is a full decode and redraw of a
            // twelve-megapixel photograph, and the shutter animation is still
            // on screen. `Task.detached` rather than a bare `await` because
            // the target builds with approachable concurrency, under which a
            // nonisolated `async` call would inherit this actor and run here.
            let upright = await Task.detached(priority: .userInitiated) {
                CameraEngine.upright(raw)
            }.value

            guard let image = UIImage(data: upright) else {
                throw CameraFailure.captureFailed
            }

            capture = Capture(data: upright, image: image)
            phase = .review
            // Nothing to preview while the still is up, and the sensor is the
            // most expensive thing the app can leave running.
            await engine.stop()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func retake() async {
        capture = nil
        phase = .ready
        await engine.start()
    }
}
