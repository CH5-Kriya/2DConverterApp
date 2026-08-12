import SwiftUI
import UIKit

struct RecentScansPanel: View {
    @Environment(AppState.self) private var appState
    let recent: [Project]

    var body: some View {
        VStack(spacing: 0) {
            header
            rows
            Spacer(minLength: 0)
        }
        .background(
            Theme.Palette.surface.opacity(0.55),
            in: RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius, style: .continuous)
        )
    }

    private var header: some View {
        HStack {
            Text("Recent Scans")
                .font(Theme.Typography.heading)
                .foregroundStyle(Theme.Palette.textPrimary)

            Spacer(minLength: 12)

            Button("See all") {
                appState.select(.myScans)
            }
            .font(.system(size: 17))
            .foregroundStyle(Theme.Palette.textSecondary)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 28)
        .frame(height: 76)
        .background(Theme.Palette.surface.opacity(0.9))
    }

    private var rows: some View {
        VStack(spacing: 0) {
            ForEach(recent) { project in
                NavigationLink(value: AppDestination.project(project.id)) {
                    RecentScanRow(project: project)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct RecentScanRow: View {
    let project: Project

    private static let dateFormat = Date.FormatStyle()
        .weekday(.abbreviated)
        .day()
        .month(.abbreviated)
        .year()

    var body: some View {
        HStack(spacing: 20) {
            thumbnail

            VStack(alignment: .leading, spacing: 4) {
                Text(project.name)
                    .font(Theme.Typography.rowTitle)
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .lineLimit(1)

                Text(project.createdAt, format: Self.dateFormat)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }

            Spacer(minLength: 12)

            Image(systemName: "chevron.right")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Theme.Palette.textPrimary)
        }
        .padding(.horizontal, 28)
        .frame(height: 96)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var thumbnail: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Theme.Palette.surfaceSelected)
            .frame(width: 72, height: 72)
            .overlay {
                if let data = project.sourceImageData, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
    }
}

#Preview {
    NavigationStack {
        RecentScansPanel(recent: Project.samples)
            .frame(width: 455, height: 450)
            .padding()
    }
    .environment(AppState())
    .background(Theme.Palette.canvas)
    .preferredColorScheme(.dark)
}
