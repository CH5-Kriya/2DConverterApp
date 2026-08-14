import SwiftUI

/// The waiting state. Small, centred, and cancellable — building the solid is
/// the long pole in this pipeline and a person should never feel trapped by it.
struct ExportProgressDialog: View {
    let stage: ExportStage
    let onCancel: () -> Void

    private var fraction: Double {
        if case .running(let value, _, _) = stage { return value }
        return 0
    }

    private var phase: String {
        if case .running(_, let label, _) = stage { return label }
        return ""
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 22) {
                Text("Exporting artwork")
                    .font(Theme.Typography.heading)
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .frame(maxWidth: .infinity)

                ProgressView(value: fraction)
                    .tint(Theme.Palette.action)
                    .scaleEffect(x: 1, y: 1.6, anchor: .center)

                HStack {
                    // The remaining line is derived from elapsed wall clock, so
                    // it needs a heartbeat. `TimelineView` gives one without
                    // pulling in Combine, which this app deliberately avoids.
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        // The phase until the rate is measurable, the countdown
                        // after. Never a number invented before there was
                        // anything to measure.
                        Text(stage.remaining?.remainingPhrase ?? phase)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Palette.textSecondary)
                    }

                    Spacer()

                    Text("\(Int(fraction * 100))%")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .monospacedDigit()
                }

                HStack {
                    Spacer()
                    Button("cancel", action: onCancel)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.textPrimary)
                        .padding(.horizontal, 30)
                        .frame(height: 46)
                        .background(Theme.Palette.surfaceSelected,
                                    in: RoundedRectangle(cornerRadius: 10,
                                                         style: .continuous))
                        .buttonStyle(.plain)
                }
            }
            .padding(34)
            .frame(width: 560)
            .background(Theme.Palette.surface,
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .accessibilityAddTraits(.isModal)
        }
    }
}

#Preview {
    ExportProgressDialog(
        stage: .running(fraction: 0.4, phase: "Building the solid",
                        started: .now.addingTimeInterval(-8))
    ) {}
    .preferredColorScheme(.dark)
}
