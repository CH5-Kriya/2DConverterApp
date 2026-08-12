import SwiftUI
import UIKit

struct ProjectDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: ProjectDetailViewModel

    init(projectID: UUID, dependencies: AppDependencies) {
        _model = State(initialValue: ProjectDetailViewModel(
            projectID: projectID,
            projects: dependencies.projects
        ))
    }

    var body: some View {
        ScreenScaffold(title: model.project?.name ?? "Project",
                       subtitle: model.project?.status.label) {
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

                EmptyStateView(
                    systemImage: "cube.transparent",
                    title: "Preview not wired up",
                    message: "The 2.5D preview and its controls go here once the conversion screens are designed."
                )
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
