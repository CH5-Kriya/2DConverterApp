import SwiftUI

struct StartNewProjectCard: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 31) {
                Image(systemName: "plus")
                    .font(.system(size: 82, weight: .medium))
                    .foregroundStyle(Theme.Palette.white)

                VStack(spacing: 5) {
                    Text("Start new project")
                        .font(Theme.Typography.heading)
                        .foregroundStyle(Theme.Palette.white)

                    Text("Turn visual art into something you can feel.")
                        .font(Theme.Typography.meta)
                        .foregroundStyle(Theme.Palette.textInactive)
                }
                .multilineTextAlignment(.center)
            }
            .padding(32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.Palette.cardFill)
            // Dashed, because the card is an invitation to put something here
            // rather than a thing that already exists.
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Metrics.panelRadius, style: .continuous)
                    .strokeBorder(Theme.Palette.white,
                                  style: StrokeStyle(lineWidth: 1, dash: [8, 6]))
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Metrics.panelRadius,
                                        style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Start new project")
        .accessibilityHint("Turn visual art into something you can feel.")
    }
}

#Preview {
    StartNewProjectCard {}
        .frame(width: 457, height: 453)
        .padding()
        .background(Theme.Palette.canvas)
        .preferredColorScheme(.dark)
}
