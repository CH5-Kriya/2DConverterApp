import SwiftUI
import UIKit

/// Shared date rendering: the mock spells it "Mon - 10 Aug 2026", which is a
/// weekday the eye can anchor on plus an unambiguous date.
private let scanDateFormat = Date.FormatStyle()
    .weekday(.abbreviated)
    .day()
    .month(.abbreviated)
    .year()

private func scanDateText(_ date: Date) -> String {
    date.formatted(scanDateFormat)
        .replacingOccurrences(of: ", ", with: " - ")
}

/// A project's thumbnail, or the empty plate it will occupy once one exists.
private struct ScanThumbnail: View {
    let project: Project
    var cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Theme.Palette.surfaceSelected)
            .overlay {
                if let data = project.thumbnail, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius,
                                                    style: .continuous))
                }
            }
    }
}

// MARK: - List

struct ScanListRow: View {
    let project: Project

    var body: some View {
        HStack(spacing: 26) {
            ScanThumbnail(project: project, cornerRadius: 10)
                .frame(width: 76, height: 76)

            VStack(alignment: .leading, spacing: 6) {
                Text(project.name)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .lineLimit(1)

                Text(scanDateText(project.createdAt))
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }

            Spacer(minLength: 16)

            Image(systemName: "chevron.right")
                .font(.system(size: 21, weight: .medium))
                .foregroundStyle(Theme.Palette.textPrimary)
        }
        .padding(.vertical, 14)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(project.name), \(scanDateText(project.createdAt))")
    }
}

// MARK: - Grid

struct ScanGridCard: View {
    let project: Project

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScanThumbnail(project: project, cornerRadius: 12)
                .aspectRatio(1, contentMode: .fit)

            VStack(alignment: .leading, spacing: 3) {
                Text(project.name)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .lineLimit(1)

                Text(scanDateText(project.createdAt))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            .padding(.bottom, 2)
        }
        .padding(14)
        .background(Theme.Palette.surface,
                    in: RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius,
                                         style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(project.name), \(scanDateText(project.createdAt))")
    }
}

#if DEBUG
#Preview("List") {
    VStack(spacing: 0) {
        ForEach(Project.previewSamples) { ScanListRow(project: $0) }
    }
    .padding(40)
    .background(Theme.Palette.canvas)
    .preferredColorScheme(.dark)
}

#Preview("Grid") {
    HStack(spacing: 24) {
        ForEach(Project.previewSamples) { ScanGridCard(project: $0).frame(width: 260) }
    }
    .padding(40)
    .background(Theme.Palette.canvas)
    .preferredColorScheme(.dark)
}
#endif
