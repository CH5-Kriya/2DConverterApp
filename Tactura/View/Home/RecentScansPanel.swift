import SwiftUI
import UIKit

struct RecentScansPanel: View {
    @Environment(AppState.self) private var appState
    let recent: [Project]

    var body: some View {
        VStack(spacing: 0) {
            header
            rows
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Palette.panelFill)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Metrics.panelRadius,
                                    style: .continuous))
    }

    private var header: some View {
        HStack {
            Text("Recent Scans")
                .font(Theme.Typography.panelTitle)
                .foregroundStyle(Theme.Palette.white)

            Spacer(minLength: 12)

            Button("See all") { appState.select(.myScans) }
                .font(Theme.Typography.link)
                .foregroundStyle(Theme.Palette.textTertiary)
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
        .background(Theme.Palette.cardFill)
    }

    private var rows: some View {
        VStack(spacing: 24) {
            ForEach(recent) { project in
                NavigationLink(value: AppDestination.project(project.id)) {
                    RecentScanRow(project: project)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
    }
}

private struct RecentScanRow: View {
    let project: Project

    var body: some View {
        HStack(spacing: 28) {
            thumbnail

            // Claims the space the thumbnail and chevron leave. Without the
            // priority SwiftUI is free to compress a one-line Text to nothing,
            // which on a narrow layout left the row showing an image, an arrow,
            // and no name at all.
            VStack(alignment: .leading, spacing: 12) {
                Text(project.name)
                    .font(Theme.Typography.listTitle)
                    .foregroundStyle(Theme.Palette.white)
                    .lineLimit(1)

                Text(date)
                    .font(Theme.Typography.meta)
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            Image(systemName: "chevron.right")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(Theme.Palette.textTertiary)
                .frame(width: 40, height: 40)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var date: String {
        let day = project.createdAt.formatted(.dateTime.weekday(.abbreviated))
        let rest = project.createdAt.formatted(.dateTime.day().month(.abbreviated).year())
        return "\(day) - \(rest)"
    }

    private var thumbnail: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Theme.Palette.thumbnailFill)
            .frame(width: 68, height: 68)
            .overlay {
                if let data = project.thumbnail, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        RecentScansPanel(recent: Project.previewSamples)
            .frame(width: 457, height: 453)
            .padding()
    }
    .environment(AppState())
    .background(Theme.Palette.canvas)
    .preferredColorScheme(.dark)
}
#endif
