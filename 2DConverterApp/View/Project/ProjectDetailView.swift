import SwiftUI
import ReliefCore
import UIKit

struct ProjectDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: ProjectDetailViewModel
    @State private var showingExport = false

    init(projectID: UUID, dependencies: AppDependencies) {
        _model = State(initialValue: ProjectDetailViewModel(
            projectID: projectID,
            projects: dependencies.projects,
            relief: dependencies.relief
        ))
    }

    var body: some View {
        ScreenScaffold(title: model.project?.name ?? "Project",
                       subtitle: model.summary ?? model.project?.status.label) {
            content
        } accessory: {
            Button {
                dismiss()
            } label: {
                Label("Back", systemImage: "chevron.left")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .task { await model.load() }
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(isPresented: $showingExport) {
            if let height = model.height {
                ExportSheet(projectName: model.project?.name ?? "relief",
                            preview: model.preview,
                            height: height,
                            config: model.currentConfig(),
                            relief: model.relief)
                    .presentationBackground(.clear)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let project = model.project {
            HStack(alignment: .top, spacing: 32) {
                sourceImage(for: project)
                    .frame(maxWidth: .infinity)

                reliefPanel
                    .frame(maxWidth: .infinity)
            }
        } else {
            EmptyStateView(
                systemImage: "questionmark.folder",
                title: "Project not found",
                message: "It may have been deleted."
            )
        }
    }

    // MARK: - Relief

    @ViewBuilder
    private var reliefPanel: some View {
        VStack(alignment: .leading, spacing: 24) {
            preview

            switch model.stage {
            case .converting(let label, let fraction):
                progress(label: label, fraction: fraction)
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Color(hex: 0xE06C6C))
            case .ready:
                refinement
                exportRow
            case .idle:
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private var preview: some View {
        RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius, style: .continuous)
            .fill(Theme.Palette.surface)
            .aspectRatio(4 / 3, contentMode: .fit)
            .overlay {
                if let cg = model.preview {
                    // Raking light, not a flat height map: a grazing key light
                    // is how relief legibility is actually judged by eye.
                    Image(decorative: cg, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius,
                                                    style: .continuous))
                } else {
                    Image(systemName: "cube.transparent")
                        .font(.system(size: 34, weight: .light))
                        .foregroundStyle(Theme.Palette.textTertiary)
                }
            }
    }

    @ViewBuilder
    private func progress(label: String, fraction: Double) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.textSecondary)
            ProgressView(value: fraction)
                .tint(Theme.Palette.accentFill)
        }
    }

    @ViewBuilder
    private var refinement: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Refine")
                    .font(Theme.Typography.rowTitle)
                    .foregroundStyle(Theme.Palette.textPrimary)
                Spacer()
                Button("Reset") { model.resetSliders() }
                    .font(Theme.Typography.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }

            slider("Depth", value: $model.depth)
            slider("Smoothness", value: $model.smoothness)
            slider("Texture", value: $model.texture)
            slider("Outline", value: $model.outline)
        }
    }

    @ViewBuilder
    private func slider(_ title: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.textSecondary)
            Slider(value: value, in: 0...1) { editing in
                // Recompute when the finger lifts. The blend itself is cheap,
                // but re-running it on every touch event is wasted work.
                if !editing { model.refine() }
            }
            .tint(Theme.Palette.accentFill)
        }
    }

    @ViewBuilder
    private var exportRow: some View {
        Button {
            showingExport = true
        } label: {
            Text("Export")
                .font(Theme.Typography.button)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(Theme.Palette.action,
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Source

    @ViewBuilder
    private func sourceImage(for project: Project) -> some View {
        RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius, style: .continuous)
            .fill(Theme.Palette.surface)
            .aspectRatio(4 / 3, contentMode: .fit)
            .overlay {
                if let data = project.sourceImageData, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius,
                                                    style: .continuous))
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 34, weight: .light))
                        .foregroundStyle(Theme.Palette.textTertiary)
                }
            }
    }
}

#Preview(traits: .landscapeLeft) {
    ProjectDetailView(projectID: Project.samples[0].id, dependencies: .preview)
        .background(Theme.Palette.canvas)
        .preferredColorScheme(.dark)
}
