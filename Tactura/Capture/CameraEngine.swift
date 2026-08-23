import AVFoundation
import CoreMedia
import Foundation
import UIKit

nonisolated enum CameraFailure: LocalizedError {
    case noCamera
    case configurationFailed
    case captureFailed

    var errorDescription: String? {
        switch self {
        case .noCamera:
            "This device has no camera available to the app."
        case .configurationFailed:
            "The camera could not be started."
        case .captureFailed:
            "That photo could not be saved. Try again."
        }
    }
}

/// Everything AVFoundation touches, and the one queue it is allowed to be
/// touched on.
///
/// The target builds with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so an
/// unannotated type here would be main-actor isolated — and `startRunning()`
/// alone blocks for a good fraction of a second. Hence `nonisolated` plus a
/// private serial queue, which is also the serialisation AVFoundation asks for
/// around session configuration.
///
/// `@unchecked Sendable` is honest rather than lazy: every mutable property
/// below is read and written only inside `queue`. `session` is the exception,
/// and deliberately so — the preview layer takes it on the main thread, which
/// is what AVFoundation expects of that one object.
nonisolated final class CameraEngine: @unchecked Sendable {

    /// Handed to the preview layer, and to nothing else.
    let session = AVCaptureSession()

    /// Resolved once, at init, so the caller can ask "is there a camera at all"
    /// before it asks anyone for permission to use it. On the simulator this is
    /// `nil`, which is the whole reason the question is worth asking first.
    let device: AVCaptureDevice?

    private let queue = DispatchQueue(label: "com.kriya.tactura.camera-session")
    private let output = AVCapturePhotoOutput()
    private var isConfigured = false

    /// `capturePhoto(with:delegate:)` does not retain its delegate. Nothing
    /// else holds these for the second or two between shutter and JPEG, so
    /// this does, keyed so each one can retire itself.
    private var inFlight: [UUID: PhotoDelegate] = [:]

    init() {
        device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
            ?? AVCaptureDevice.default(for: .video)
    }

    /// The active format's aspect, sensor-side, so the preview can be given the
    /// shape of the photograph it is previewing. Meaningful only once
    /// `configure()` has settled the format; zero until then.
    var sensorAspect: CGFloat {
        guard let device else { return 0 }
        let size = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
        guard size.height > 0 else { return 0 }
        return CGFloat(size.width) / CGFloat(size.height)
    }

    // MARK: Session

    func configure() async throws {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    try self.configureOnQueue()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func start() async {
        await withCheckedContinuation { continuation in
            queue.async {
                if self.isConfigured, !self.session.isRunning {
                    self.session.startRunning()
                }
                continuation.resume()
            }
        }
    }

    func stop() async {
        await withCheckedContinuation { continuation in
            queue.async {
                if self.session.isRunning { self.session.stopRunning() }
                continuation.resume()
            }
        }
    }

    private func configureOnQueue() throws {
        guard !isConfigured else { return }
        guard let device else { throw CameraFailure.noCamera }

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        // Stills, not video: this preset picks the format that can actually
        // deliver the sensor's full photo resolution, which is the point of
        // scanning rather than screenshotting.
        session.sessionPreset = .photo

        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input), session.canAddOutput(output) else {
            throw CameraFailure.configurationFailed
        }
        session.addInput(input)
        session.addOutput(output)

        // Read *after* the preset has chosen the active format, or this asks
        // for dimensions the format cannot produce and the capture fails.
        if let largest = device.activeFormat.supportedMaxPhotoDimensions
            .max(by: { Int($0.width) * Int($0.height) < Int($1.width) * Int($1.height) }) {
            output.maxPhotoDimensions = largest
        }
        output.maxPhotoQualityPrioritization = .quality

        configureFocus(on: device)
        isConfigured = true
    }

    /// Continuous autofocus, and metering weighted to the middle of the frame:
    /// artwork fills the frame, so the centre is the subject rather than a
    /// guess about it.
    private func configureFocus(on device: AVCaptureDevice) {
        guard (try? device.lockForConfiguration()) != nil else { return }
        defer { device.unlockForConfiguration() }

        if device.isFocusModeSupported(.continuousAutoFocus) {
            device.focusMode = .continuousAutoFocus
        }
        if device.isExposureModeSupported(.continuousAutoExposure) {
            device.exposureMode = .continuousAutoExposure
        }
        if device.isSmoothAutoFocusSupported {
            // Off: nothing here is moving, and the smoothing exists to hide
            // focus racking in video.
            device.isSmoothAutoFocusEnabled = false
        }
    }

    /// `point` is in the capture device's own normalised space — the preview
    /// layer converts a tap into it.
    func focus(at point: CGPoint) {
        queue.async {
            guard let device = self.device,
                  (try? device.lockForConfiguration()) != nil else { return }
            defer { device.unlockForConfiguration() }

            if device.isFocusPointOfInterestSupported,
               device.isFocusModeSupported(.autoFocus) {
                device.focusPointOfInterest = point
                device.focusMode = .autoFocus
            }
            if device.isExposurePointOfInterestSupported,
               device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposurePointOfInterest = point
                device.exposureMode = .continuousAutoExposure
            }
        }
    }

    // MARK: Capture

    /// `rotationAngle` comes from the device's rotation coordinator, so a photo
    /// taken with the iPad on its side is upright rather than sideways.
    func capture(rotationAngle: CGFloat) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                guard self.isConfigured else {
                    continuation.resume(throwing: CameraFailure.configurationFailed)
                    return
                }

                if let connection = self.output.connection(with: .video),
                   connection.isVideoRotationAngleSupported(rotationAngle) {
                    connection.videoRotationAngle = rotationAngle
                }

                let token = UUID()
                let delegate = PhotoDelegate { [weak self] result in
                    self?.retire(token)
                    continuation.resume(with: result)
                }
                self.inFlight[token] = delegate
                self.output.capturePhoto(with: self.photoSettings(), delegate: delegate)
            }
        }
    }

    private func retire(_ token: UUID) {
        queue.async { self.inFlight[token] = nil }
    }

    private func photoSettings() -> AVCapturePhotoSettings {
        // JPEG rather than the HEIF default. Everything downstream — the
        // thumbnail, the cropper, the pipeline's loader — goes through ImageIO
        // and would read either, but the crop step re-encodes as JPEG anyway,
        // so starting there costs nothing and keeps one format on disk.
        let settings = output.availablePhotoCodecTypes.contains(.jpeg)
            ? AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
            : AVCapturePhotoSettings()

        settings.maxPhotoDimensions = output.maxPhotoDimensions
        settings.photoQualityPrioritization = .quality
        if output.supportedFlashModes.contains(.off) {
            settings.flashMode = .off
        }
        return settings
    }

    // MARK: Orientation

    /// Rotates the pixels to match the photograph's orientation flag, and drops
    /// the flag.
    ///
    /// The crop screen measures its rectangle against `UIImage.size`, which has
    /// the flag applied, and makes the cut against `CGImage`, which does not.
    /// For an upright import the two agree; for a photograph taken with the
    /// iPad on its side they are transposed, and the crop lands somewhere the
    /// person never drew. Spending the flag once, here, is what keeps the rest
    /// of the flow honest — and it is the capture path that makes rotated
    /// imports the norm rather than the exception.
    ///
    /// Returns the original data when there is nothing to do, so an upright
    /// shot is never re-encoded.
    static func upright(_ data: Data) -> Data {
        guard let image = UIImage(data: data), image.imageOrientation != .up else { return data }

        let format = UIGraphicsImageRendererFormat.preferred()
        format.scale = 1
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        let redrawn = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
        return redrawn.jpegData(compressionQuality: 0.95) ?? data
    }
}

/// One shot, one delegate. AVFoundation calls these back on a queue of its own
/// choosing, which is why the class is `nonisolated`.
private nonisolated final class PhotoDelegate: NSObject, AVCapturePhotoCaptureDelegate,
                                               @unchecked Sendable {

    private let completion: (Result<Data, Error>) -> Void
    /// Both callbacks below can fire for a single shot; a continuation may only
    /// be resumed once.
    private var hasFinished = false

    init(completion: @escaping (Result<Data, Error>) -> Void) {
        self.completion = completion
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        if let error {
            finish(.failure(error))
        } else if let data = photo.fileDataRepresentation() {
            finish(.success(data))
        } else {
            finish(.failure(CameraFailure.captureFailed))
        }
    }

    /// The backstop: if the shot fails before there is a photo to process, the
    /// call above never arrives and this is the only thing that resumes.
    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings,
                     error: Error?) {
        finish(.failure(error ?? CameraFailure.captureFailed))
    }

    private func finish(_ result: Result<Data, Error>) {
        guard !hasFinished else { return }
        hasFinished = true
        completion(result)
    }
}
