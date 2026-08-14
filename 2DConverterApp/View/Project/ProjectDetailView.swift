import SwiftUI

/// The editing workspace: the converted relief in 3D, with the parameters that
/// shape it alongside. The whole screen exists so the two can be read together —
/// a slider whose effect you can't see is just a number.
struct ProjectDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: ProjectDetailViewModel
    @State private var exportedURL: URL?
    @State private var isRenaming = false
    @State private var draftName = ""

    init(projectID: UUID, dependencies: AppDependencies) {
        _model = State(initialValue: ProjectDetailViewModel(
            projectID: projectID,
            projects: dependencies.projects,
            relief: dependencies.relief
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            content
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Palette.workspaceCanvas)
        .task { await model.load() }
        .toolbar(.hidden, for: .navigationBar)
        .alert("Rename Project", isPresented: $isRenaming) {
            TextField("Name", text: $draftName)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                Task { await model.rename(to: draftName) }
            }
            .disabled(draftName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    // MARK: - Header

    private var header: some View {
        ZStack {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Label("Back", systemImage: "chevron.backward")
                        .labelStyle(.titleAndIcon)
                        .padding(.horizontal, 12)
                }
                .buttonStyle(.workspaceChip)
                Spacer()
            }

            Button {
                draftName = model.project?.name ?? ""
                isRenaming = true
            } label: {
                HStack(spacing: 8) {
                    Text(model.project?.name ?? "Project")
                        .font(.system(size: 24))
                        .underline()
                        .foregroundStyle(Theme.Palette.workspaceLabel.opacity(0.9))
                    Image("RenameProject")
                        .resizable()
                        .renderingMode(.template)
                        .frame(width: 18, height: 18)
                        .foregroundStyle(Theme.Palette.workspaceLabel.opacity(0.9))
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Rename project")
        }
        .frame(height: Theme.Metrics.workspaceControlHeight)
    }

    // MARK: - Body

    private var content: some View {
        HStack(alignment: .bottom, spacing: 24) {
            VStack(spacing: 16) {
                viewport
                HStack {
                    Spacer()
                    historyControls
                }
            }

            VStack(spacing: 0) {
                Spacer(minLength: 0)
                configurationPanel
                Spacer(minLength: 0)
                exportButton
            }
            .frame(width: Theme.Metrics.workspacePanelWidth)
        }
        .padding(.top, 16)
    }

    /// One state at a time. The 3D view renders whatever mesh it is given and
    /// nothing else, so the screen — which is the only thing that knows why
    /// there is no mesh — owns every empty and in-flight state.
    @ViewBuilder
    private var viewport: some View {
        switch model.stage {
        case .failed(let message):
            EmptyStateView(systemImage: "exclamationmark.triangle",
                           title: "Conversion failed",
                           message: message)

        case .idle where model.project?.sourceImageData == nil:
            EmptyStateView(systemImage: "photo.badge.plus",
                           title: "No source image",
                           message: "This project has no photo to convert.")

        case .converting(let label, let fraction):
            Relief3DPreview(mesh: model.previewMesh)
                .overlay { progress(label: label, fraction: fraction) }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .idle, .ready:
            Relief3DPreview(mesh: model.previewMesh)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func progress(label: String, fraction: Double) -> some View {
        VStack(spacing: 14) {
            Text(label)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.textSecondary)
            ProgressView(value: fraction)
                .tint(Theme.Palette.accentFill)
                .frame(width: 260)
        }
        .padding(28)
        .background(Theme.Palette.workspacePanel.opacity(0.86),
                    in: RoundedRectangle(cornerRadius: Theme.Metrics.workspacePanelRadius,
                                         style: .continuous))
    }

    private var historyControls: some View {
        HStack(spacing: 12) {
            Button {
                model.undo()
            } label: {
                Image(systemName: "arrow.uturn.left")
            }
            .buttonStyle(.workspaceChip)
            .disabled(!model.canUndo)
            .accessibilityLabel("Undo")

            Button {
                model.redo()
            } label: {
                Image(systemName: "arrow.uturn.right")
            }
            .buttonStyle(.workspaceChip)
            .disabled(!model.canRedo)
            .accessibilityLabel("Redo")
        }
        .opacity(model.canRefine ? 1 : 0.35)
    }

    // MARK: - Configuration

    private var configurationPanel: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 16) {
                sectionTitle("Preset")
                Picker("Preset", selection: presetBinding) {
                    ForEach(ProjectDetailViewModel.Preset.allCases) { preset in
                        Text(preset.rawValue).tag(preset)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 16) {
                sectionTitle("Configuration")
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(ProjectDetailViewModel.Control.allCases) { control in
                        parameterRow(control)
                    }
                }
            }
        }
        .padding(24)
        .frame(width: Theme.Metrics.workspacePanelWidth, alignment: .leading)
        .background(Theme.Palette.workspacePanel,
                    in: RoundedRectangle(cornerRadius: Theme.Metrics.workspacePanelRadius,
                                         style: .continuous))
        .disabled(!model.canRefine)
        .opacity(model.canRefine ? 1 : 0.5)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Theme.Palette.textPrimary)
    }

    private func parameterRow(_ control: ProjectDetailViewModel.Control) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(control.title)
                .font(.system(size: 14))
                .foregroundStyle(Theme.Palette.textPrimary)

            HStack(spacing: 16) {
                Slider(value: binding(for: control), in: 0...1) { editing in
                    // One drag is one edit. Committing per touch event would
                    // fill the undo stack with sixty steps nobody asked for,
                    // and re-blend on every one of them.
                    if !editing { model.commit() }
                }
                .tint(Theme.Palette.accentFill)

                Text(model.readout(for: control))
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .frame(width: 56, height: 30)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(Theme.Palette.workspaceStroke, lineWidth: 0.3)
                    )
            }
        }
    }

    private var exportButton: some View {
        VStack(spacing: 12) {
            Button("Export") {
                Task { exportedURL = await model.exportSTL() }
            }
            .buttonStyle(.kriyaAccent)
            .disabled(!model.canRefine)
            .opacity(model.canRefine ? 1 : 0.5)

            if let url = exportedURL {
                ShareLink(item: url) {
                    Label("Share STL", systemImage: "square.and.arrow.up")
                        .font(Theme.Typography.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.Palette.textSecondary)
            }

            if let summary = model.summary {
                Text(summary)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: - Bindings

    private var presetBinding: Binding<ProjectDetailViewModel.Preset> {
        Binding { model.settings.preset } set: { model.select($0) }
    }

    private func binding(for control: ProjectDetailViewModel.Control) -> Binding<Double> {
        Binding { model.value(for: control) } set: { model.setValue($0, for: control) }
    }
}

#if DEBUG
#Preview(traits: .landscapeLeft) {
    ProjectDetailView(projectID: Project.previewSamples[0].id, dependencies: .preview)
        .preferredColorScheme(.dark)
}
#endif
