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
            scrim
            card
        }
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
            appState.open(.crop(project.id), in: .myScans)
            model.clearCreatedProject()
        }
        .alert("Import failed", isPresented: $model.hasError) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var scrim: some View {
        Color.black.opacity(0.62)
            .ignoresSafeArea()
            .onTapGesture { appState.isPresentingNewProject = false }
            .accessibilityLabel("Dismiss")
            .accessibilityAddTraits(.isButton)
    }

    private var card: some View {
        VStack(spacing: 0) {
            Text("Create new project")
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Palette.textPrimary)

            Text("Choose how you'll like to add your 2D Artwork")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Palette.textSecondary)
                .padding(.top, 12)

            HStack(spacing: 47) {
                CreateOptionCard(
                    systemImage: "doc.viewfinder",
                    title: "Scan Artwork",
                    caption: "Use your camera to scan the project",
                    isEnabled: false
                ) {}

                CreateOptionCard(
                    systemImage: "photo.badge.plus",
                    title: "Import Artwork",
                    caption: "Import your project from gallery",
                    isEnabled: !model.isImporting
                ) {
                    model.isPresentingPicker = true
                }
            }
            .padding(.top, 44)
            .overlay {
                if model.isImporting {
                    ProgressView()
                        .tint(Theme.Palette.textPrimary)
                }
            }
        }
        .padding(.horizontal, 39)
        .padding(.top, 40)
        .padding(.bottom, 33)
        .frame(width: 661)
        .background(
            Theme.Palette.surface,
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
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
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                Image(systemName: systemImage)
                    .font(.system(size: 66, weight: .regular))
                    .foregroundStyle(Theme.Palette.textPrimary)
                Spacer(minLength: 24)
                Text(title)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Theme.Palette.textPrimary)
                Text(caption)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .padding(.top, 6)
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(width: 268, height: 272)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Theme.Palette.canvas)
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Theme.Palette.border, lineWidth: 1.5)
                    }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
        .accessibilityLabel("\(title). \(caption)")
    }
}

#Preview(traits: .landscapeLeft) {
    CreateProjectDialog(dependencies: .preview)
        .environment(AppState())
        .preferredColorScheme(.dark)
}
