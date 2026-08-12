import SwiftUI

struct StartNewProjectCard: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                Spacer(minLength: 0)

                Image(systemName: "plus")
                    .font(.system(size: 60, weight: .medium))
                    .foregroundStyle(Theme.Palette.textPrimary)

                Spacer(minLength: 32)

                Text("Start new project")
                    .font(Theme.Typography.heading)
                    .foregroundStyle(Theme.Palette.textPrimary)

                Text("Ready to turn your 2D into 3D again?")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .padding(.top, 6)

                Spacer(minLength: 0)
            }
            .padding(32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius, style: .continuous)
                    .strokeBorder(Theme.Palette.border, lineWidth: 1.5)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Start new project")
    }
}

#Preview {
    StartNewProjectCard {}
        .frame(width: 455, height: 450)
        .padding()
        .background(Theme.Palette.canvas)
        .preferredColorScheme(.dark)
}
