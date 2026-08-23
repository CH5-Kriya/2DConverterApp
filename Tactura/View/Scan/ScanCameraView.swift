import SwiftUI

/// "Scan Artwork" — the camera half of creating a project.
///
/// Full screen, and its own chrome rather than the system camera's, because
/// framing a painting square-on *is* the task: the crop step after this can cut
/// a rectangle out of the photograph but it cannot undo the keystone of
/// shooting from an angle, and the pipeline resamples to `work_res` on the long
/// edge — so everything in the shot that is not the artwork is detail the
/// relief never receives.
///
/// Hands back JPEG data and nothing else. The project record, the thumbnail and
/// the trip to the cropper belong to the import path, so a scan and a gallery
/// pick land in exactly the same place.
struct ScanCameraView: View {

    let onCapture: (Data) -> Void
    let onCancel: () -> Void

    @State private var model = ScanCaptureViewModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var model = model

        return ZStack {
            Theme.Palette.canvas.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                stage
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                footer
            }
            .padding(.horizontal, 40)
            .padding(.top, 32)
            .padding(.bottom, 28)
        }
        .preferredColorScheme(.dark)
        .task { await model.start() }
        // `task` is cancelled when the cover goes away, but tearing the session
        // down is work of its own — the sensor stays powered until it runs.
        .onDisappear { Task { await model.stop() } }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await model.resume() }
        }
        .alert("Capture failed", isPresented: $model.hasError) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    // MARK: Header

    private var header: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 8) {
                Text("Scan Artwork")
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Palette.textPrimary)
                Text(subtitle)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)

            HStack {
                Button(action: onCancel) {
                    Label("Cancel", systemImage: "chevron.left")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Theme.Palette.onAccent)
                        .padding(.horizontal, 18)
                        .frame(height: 46)
                        .background(Theme.Palette.accentFill, in: Capsule())
                }
                .buttonStyle(.plain)
                Spacer()
            }
        }
    }

    private var subtitle: String {
        switch model.phase {
        case .ready:  "Fill the frame with the artwork, square on. Tap to focus."
        case .review: "Happy with it? Crop comes next."
        default:      "Use your camera to scan the project"
        }
    }

    // MARK: Stage

    @ViewBuilder
    private var stage: some View {
        Group {
            switch model.phase {
            case .preparing:
                ProgressView()
                    .tint(Theme.Palette.textPrimary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .ready:
                CameraPreviewView(session: model.session,
                                  rotationAngle: model.previewRotation) { point in
                    model.focus(at: point)
                }
                .aspectRatio(model.previewAspect, contentMode: .fit)
                .overlay {
                    FramingGuide()
                        .stroke(Theme.Palette.textPrimary.opacity(0.6),
                                style: StrokeStyle(lineWidth: 3, lineCap: .round))
                }
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

            case .review:
                if let image = model.capture?.image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                }

            case .denied:
                deniedState

            case .unavailable(let message):
                EmptyStateView(systemImage: "video.slash",
                               title: "Camera unavailable",
                               message: message)
            }
        }
        .padding(.vertical, 28)
    }

    private var deniedState: some View {
        VStack(spacing: 24) {
            EmptyStateView(
                systemImage: "lock.slash",
                title: "Camera access is off",
                message: """
                    Tactura needs the camera to scan artwork. Turn it on in \
                    Settings, or import from your gallery instead.
                    """)
            .fixedSize(horizontal: false, vertical: true)

            Button("Open Settings") {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            }
            .buttonStyle(.tacturaSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Footer

    @ViewBuilder
    private var footer: some View {
        switch model.phase {
        case .ready:
            shutter

        case .review:
            HStack(spacing: 20) {
                Button("Retake") { Task { await model.retake() } }
                    .buttonStyle(.tacturaSecondary)

                Button {
                    guard let data = model.capture?.data else { return }
                    onCapture(data)
                } label: {
                    // Blue, like Continue on the crop step: the one control on
                    // the screen that carries the project forward.
                    Text("Use Photo")
                        .font(Theme.Typography.button)
                        .foregroundStyle(.white)
                        .frame(width: Theme.Metrics.buttonWidth,
                               height: Theme.Metrics.buttonHeight)
                        .background(Theme.Palette.action,
                                    in: RoundedRectangle(cornerRadius: Theme.Metrics.buttonRadius,
                                                         style: .continuous))
                }
                .buttonStyle(.plain)
            }

        default:
            EmptyView()
        }
    }

    private var shutter: some View {
        Button {
            Task { await model.takePhoto() }
        } label: {
            ZStack {
                Circle()
                    .strokeBorder(Theme.Palette.textPrimary.opacity(0.9), lineWidth: 4)
                    .frame(width: 86, height: 86)
                Circle()
                    .fill(Theme.Palette.accentFill)
                    .frame(width: 70, height: 70)
                    .opacity(model.isCapturing ? 0.3 : 1)
                if model.isCapturing {
                    ProgressView().tint(Theme.Palette.onAccent)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(model.isCapturing)
        .accessibilityLabel("Take photo")
    }
}

/// Four corner brackets rather than a full rectangle: the guide has to say
/// "aim here" without drawing a line across the artwork being judged.
private struct FramingGuide: Shape {
    var inset: CGFloat = 24
    var armLength: CGFloat = 52

    func path(in rect: CGRect) -> Path {
        let frame = rect.insetBy(dx: inset, dy: inset)
        guard frame.width > 0, frame.height > 0 else { return Path() }
        let arm = min(armLength, min(frame.width, frame.height) / 3)

        let corners: [(x: CGFloat, y: CGFloat, dx: CGFloat, dy: CGFloat)] = [
            (frame.minX, frame.minY,  1,  1),
            (frame.maxX, frame.minY, -1,  1),
            (frame.minX, frame.maxY,  1, -1),
            (frame.maxX, frame.maxY, -1, -1),
        ]

        var path = Path()
        for corner in corners {
            path.move(to: CGPoint(x: corner.x + corner.dx * arm, y: corner.y))
            path.addLine(to: CGPoint(x: corner.x, y: corner.y))
            path.addLine(to: CGPoint(x: corner.x, y: corner.y + corner.dy * arm))
        }
        return path
    }
}
