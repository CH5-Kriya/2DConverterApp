import SwiftUI
import UIKit

struct ProjectCard: View {
    let project: Project

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            thumbnail

            VStack(alignment: .leading, spacing: 6) {
                Text(project.name)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    StatusBadge(status: project.status)
                    Text(project.createdAt, format: .relative(presentation: .named))
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.textTertiary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(project.name), \(project.status.label)")
    }

    private var thumbnail: some View {
        RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius, style: .continuous)
            .fill(Theme.Palette.surface)
            .aspectRatio(4 / 3, contentMode: .fit)
            .overlay {
                if let data = project.sourceImageData, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius,
                                                    style: .continuous))
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 30, weight: .light))
                        .foregroundStyle(Theme.Palette.textTertiary)
                }
            }
    }
}

struct StatusBadge: View {
    let status: ProjectStatus

    var body: some View {
        Text(status.label)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(tint.opacity(0.14), in: Capsule())
    }

    private var tint: Color {
        switch status {
        case .draft:     Theme.Palette.textSecondary
        case .analyzing: Color(hex: 0xE0B341)
        case .ready:     Color(hex: 0x5FC26B)
        case .exported:  Color(hex: 0x6FA8FF)
        case .failed:    Color(hex: 0xE06C6C)
        }
    }
}

#if DEBUG
#Preview {
    ProjectCard(project: Project.previewSamples[0])
        .frame(width: 280)
        .padding()
        .background(Theme.Palette.canvas)
        .preferredColorScheme(.dark)
}
#endif
