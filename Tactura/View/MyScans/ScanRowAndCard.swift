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
                }
            }
            // Clipped here, on the plate, rather than on the image.
            //
            // `ProjectThumbnail` bounds the long edge and leaves the import's
            // aspect ratio alone, so these are rarely square, and `.fill`
            // reports the *filled* size — larger than the plate on one axis.
            // A clip shape on the image is therefore cut to the overflow rather
            // than to the plate and holds nothing back: a portrait scan drew
            // over its own title, a wide one over the card beside it, and no
            // two tiles read as the same size.
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

// MARK: - List

struct ScanListRow: View {
    let project: Project

    var body: some View {
        HStack(spacing: 32) {
            ScanThumbnail(project: project, cornerRadius: 11)
                .frame(width: 72, height: 72)

            VStack(alignment: .leading, spacing: 12) {
                Text(project.name)
                    .font(Theme.Typography.scanRowTitle)
                    .foregroundStyle(Theme.Palette.white)
                    .lineLimit(1)

                Text(scanDateText(project.createdAt))
                    .font(Theme.Typography.subheadline)
                    .foregroundStyle(Theme.Palette.textInactive)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            Image(systemName: "chevron.right")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(Theme.Palette.textInactive)
                .frame(width: 40, height: 40)
        }
        .frame(height: 72)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(project.name), \(scanDateText(project.createdAt))")
    }
}

// MARK: - Grid

struct ScanGridCard: View {
    let project: Project

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // A fixed height, not a square. The design gives every card the
            // same 220 pt window whatever shape the artwork is, which is what
            // keeps a row of them level.
            ScanThumbnail(project: project, cornerRadius: 9)
                .frame(height: 220)

            VStack(alignment: .leading, spacing: 8) {
                Text(project.name)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Theme.Palette.white)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(scanDateText(project.createdAt))
                    .font(Theme.Typography.subheadline)
                    .foregroundStyle(Theme.Palette.textInactive)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Palette.elevatedFill,
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
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
