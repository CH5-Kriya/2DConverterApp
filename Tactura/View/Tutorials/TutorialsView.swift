import SwiftUI

struct TutorialsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 44) {
            header

            HStack(alignment: .top, spacing: 20) {
                ForEach(TutorialStep.all) { step in
                    StepCard(step: step)
                }
            }
        }
        .padding(.horizontal, Theme.Metrics.contentPadding)
        .padding(.top, 44)
        .padding(.bottom, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 8) {
                Text("How to convert your image")
                    .font(.system(size: 35, weight: .bold))
                    .foregroundStyle(Theme.Palette.white)

                Text("Follow this simple steps to turn your 2D images into 2.5D models")
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(Theme.Palette.white)
            }

            Spacer(minLength: 24)

            Button {
                appState.isPresentingNewProject = true
            } label: {
                Label("Create Project", systemImage: "plus")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 19)
                    .padding(.vertical, 17)
                    .background(Theme.Palette.action,
                                in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .buttonStyle(.plain)
            .fixedSize()
        }
    }
}

// MARK: - Content

struct TutorialStep: Identifiable {
    struct Row: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let caption: String
    }

    let id = UUID()
    let number: Int
    let title: String
    /// Stands in for the walkthrough image the design reserves space for.
    let placeholder: String
    let rows: [Row]

    static let all: [TutorialStep] = [
        TutorialStep(
            number: 1,
            title: "Prepare Your 2D Image",
            placeholder: "photo.on.rectangle.angled",
            rows: [
                Row(icon: "camera.fill", title: "Take a photo",
                    caption: "Use your camera to capture your image"),
                Row(icon: "photo.fill", title: "Import from gallery",
                    caption: "Choose an existing image from gallery"),
                Row(icon: "lightbulb.max.fill", title: "Tips",
                    caption: "Use a clear & well lit image for best result"),
            ]
        ),
        TutorialStep(
            number: 2,
            title: "Crop & Convert",
            placeholder: "crop",
            rows: [
                Row(icon: "crop", title: "Crop",
                    caption: "Adjust the frame to the selected area"),
                Row(icon: "sparkles", title: "Convert",
                    caption: "Let our system analyzes the image and turn it into 2.5D model"),
                Row(icon: "cube.fill", title: "Almost there",
                    caption: "Once the conversion is complete, it\u{2019}s time to refine your model"),
            ]
        ),
        TutorialStep(
            number: 3,
            title: "Refine & Export",
            placeholder: "slider.horizontal.3",
            rows: [
                Row(icon: "slider.horizontal.3", title: "Adjust your model",
                    caption: "Use the tools to fine tune your model"),
                Row(icon: "square.and.arrow.down", title: "Export model",
                    caption: "Name your project, choose the location, and set your model format"),
                Row(icon: "checkmark.seal.fill", title: "Done!",
                    caption: "Now you can use your model for projects, or print it in 3D!"),
            ]
        ),
    ]
}

// MARK: - Card

private struct StepCard: View {
    let step: TutorialStep

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("\(step.number). \(step.title)")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.Palette.white)

            VStack(alignment: .leading, spacing: 16) {
                media

                VStack(spacing: 16) {
                    ForEach(Array(step.rows.enumerated()), id: \.element.id) { index, row in
                        if index > 0 {
                            Rectangle()
                                .fill(Theme.Palette.separator)
                                .frame(height: 1)
                        }
                        StepRow(row: row)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Palette.elevatedFill,
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    /// The design reserves a 236 pt window here for a walkthrough image that
    /// does not exist yet. A dimmed symbol holds the space and reads as
    /// pending; a flat plate would read as broken.
    private var media: some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(Theme.Palette.panelFill)
            .frame(height: 236)
            .overlay {
                Image(systemName: step.placeholder)
                    .font(.system(size: 52, weight: .light))
                    .foregroundStyle(Theme.Palette.textInactive)
            }
            .accessibilityHidden(true)
    }
}

private struct StepRow: View {
    let row: TutorialStep.Row

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: row.icon)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Theme.Palette.selectedFill,
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text(row.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.Palette.white)

                Text(row.caption)
                    .font(.system(size: 12, weight: .light))
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // A floor rather than a fixed height: the longest caption runs to three
        // lines in the narrower column the app actually has.
        .frame(minHeight: 64)
        .accessibilityElement(children: .combine)
    }
}

#Preview(traits: .landscapeLeft) {
    TutorialsView()
        .environment(AppState())
        .background(Theme.Palette.canvas)
        .preferredColorScheme(.dark)
}
