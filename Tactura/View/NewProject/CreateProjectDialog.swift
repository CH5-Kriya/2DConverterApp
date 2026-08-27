import PhotosUI
import SwiftUI

struct CreateProjectDialog: View {
    @Environment(AppState.self) private var appState
    @State private var model: NewProjectViewModel

    init(dependencies: AppDependencies) {
        _model = State(initialValue: NewProjectViewModel(projects: dependencies.projects))
    }

    var body: some View {
        @Bindable var model = model

        ZStack {
            // The camera replaces the dialog rather than covering it. This
            // layer is already the app's full-screen modal — presenting a
            // `fullScreenCover` from here would mean UIKit dismissing the
            // camera at the same moment SwiftUI removes the thing that
            // presented it, which is how covers get stranded on screen.
            if model.isPresentingCamera {
                ScanCameraView { data in
                    model.isPresentingCamera = false
                    Task { await model.importCaptured(data) }
                } onCancel: {
                    model.isPresentingCamera = false
                }
                .transition(.opacity)
            } else {
                scrim
                card
            }
        }
        .animation(.snappy(duration: 0.22), value: model.isPresentingCamera)
        .photosPicker(
            isPresented: $model.isPresentingPicker,
            selection: $model.pickedItem,
            matching: .images,
            photoLibrary: .shared()
        )
        .onChange(of: model.pickedItem) { _, newValue in
            guard newValue != nil else { return }
            Task { await model.importPick() }
        }
        .onChange(of: model.createdProject) { _, project in
            guard let project else { return }
            appState.isPresentingNewProject = false
            // Stays in whichever section the dialog was opened from, so the
            // way back out of the flow is the way in.
            appState.replace(with: .crop(project.id))
            model.clearCreatedProject()
        }
        .alert("Import failed", isPresented: $model.hasError) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var scrim: some View {
        // The canvas colour at 80%, not black: the design dims the screen
        // rather than draining it, so the home behind stays recognisable.
        Theme.Palette.canvas.opacity(0.8)
            .ignoresSafeArea()
            .onTapGesture { appState.isPresentingNewProject = false }
            .accessibilityLabel("Dismiss")
            .accessibilityAddTraits(.isButton)
    }

    private var card: some View {
        VStack(spacing: 0) {
            Text("Create new project")
                .font(Theme.Typography.dialogTitle)
                .foregroundStyle(Theme.Palette.textPrimary)

            Text("Choose how you want to add your artwork and get started")
                .font(Theme.Typography.subheadline)
                .foregroundStyle(Theme.Palette.textInactive)
                .padding(.top, 12)

            HStack(spacing: 42) {
                CreateOptionCard(
                    systemImage: "camera.viewfinder",
                    title: "Scan Artwork",
                    caption: "Scan an artwork with your camera",
                    isEnabled: !model.isImporting
                ) {
                    model.isPresentingCamera = true
                }

                CreateOptionCard(
                    systemImage: "photo.badge.plus",
                    title: "Import Artwork",
                    caption: "Choose an artwork from your gallery",
                    isEnabled: !model.isImporting
                ) {
                    model.isPresentingPicker = true
                }
            }
            .padding(.top, 43)
            .overlay {
                if model.isImporting {
                    ProgressView()
                        .tint(Theme.Palette.textPrimary)
                }
            }
        }
        .multilineTextAlignment(.center)
        .padding(.top, 37)
        .frame(width: 663, height: 448, alignment: .top)
        .background(Theme.Palette.cardFill)
        // A hairline rather than a border: it separates the dialog from the
        // dimmed screen behind without reading as a frame around it.
        .overlay {
            RoundedRectangle(cornerRadius: 20.5, style: .continuous)
                .strokeBorder(Theme.Palette.white, lineWidth: 0.3)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20.5, style: .continuous))
        .accessibilityAddTraits(.isModal)
    }
}

private struct CreateOptionCard: View {
    let systemImage: String
    let title: String
    let caption: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 18) {
                Image(systemName: systemImage)
                    .font(.system(size: 72, weight: .regular))
                    .foregroundStyle(Theme.Palette.white)

                VStack(spacing: 6) {
                    Text(title)
                        .font(Theme.Typography.listTitle)
                        .foregroundStyle(Theme.Palette.textPrimary)

                    Text(caption)
                        .font(Theme.Typography.footnote)
                        .foregroundStyle(Theme.Palette.textInactive)
                }
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 27)
            // The card carries the same fill as the dialog it sits in; only
            // the hairline says where one ends and the other begins.
            .frame(width: 270, height: 270)
            .background(Theme.Palette.cardFill)
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(Theme.Palette.white, lineWidth: 0.3)
            }
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
        .accessibilityLabel("\(title). \(caption)")
    }
}

#if DEBUG
#Preview(traits: .landscapeLeft) {
    CreateProjectDialog(dependencies: .preview)
        .environment(AppState())
        .preferredColorScheme(.dark)
}
#endif
