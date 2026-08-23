import AVFoundation
import SwiftUI
import UIKit

/// The live feed.
///
/// A `UIViewRepresentable` because the preview is a `CALayer` the capture
/// session draws into directly — there is no SwiftUI view that takes an
/// `AVCaptureSession`.
struct CameraPreviewView: UIViewRepresentable {

    let session: AVCaptureSession
    /// Degrees, from the session's rotation coordinator.
    let rotationAngle: CGFloat
    /// A tap, already converted into the capture device's normalised space.
    var onFocus: (CGPoint) -> Void = { _ in }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        // `resizeAspect`, not `resizeAspectFill`: this is a framing tool, and
        // filling the view would crop away the edges of the picture the person
        // is lining up — the one thing they are looking at the screen to judge.
        view.previewLayer.videoGravity = .resizeAspect
        view.onFocus = onFocus
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {
        view.onFocus = onFocus
        view.apply(rotationAngle: rotationAngle)
    }

    final class PreviewView: UIView {

        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

        // swiftlint:disable:next force_cast
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

        var onFocus: (CGPoint) -> Void = { _ in }

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .black
            addGestureRecognizer(
                UITapGestureRecognizer(target: self, action: #selector(handleTap)))
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("Not loaded from a nib.") }

        func apply(rotationAngle: CGFloat) {
            guard let connection = previewLayer.connection,
                  connection.videoRotationAngle != rotationAngle,
                  connection.isVideoRotationAngleSupported(rotationAngle) else { return }
            connection.videoRotationAngle = rotationAngle
        }

        @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
            let point = previewLayer.captureDevicePointConverted(
                fromLayerPoint: gesture.location(in: self))
            onFocus(point)
        }
    }
}
