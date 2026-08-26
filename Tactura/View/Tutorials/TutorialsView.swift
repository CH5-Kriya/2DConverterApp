import SwiftUI

struct TutorialsView: View {
    @Environment(AppState.self) private var appState

    /// The three steps are one screen you page through rather than three
    /// columns side by side. A step is a sequence -- do this, then this, then
    /// this -- and three columns invite reading across instead of down.
    @State private var step = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 44) {
            header

            VStack(spacing: 24) {
                Rectangle()
                    .fill(Theme.Palette.separator)
                    .frame(height: 1)

                pager

                footer
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

    /// 504 is the height the design gives the page, and a ceiling rather than a
    /// fixed height: the window is not always 834 pt tall, and a page that
    /// cannot give any of it back would push the pager's own controls off the
    /// bottom before anything else gave way.
    private var pager: some View {
        TabView(selection: $step) {
            ForEach(Array(TutorialStep.all.enumerated()), id: \.element.id) { index, step in
                StepPage(step: step)
                    .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(maxHeight: 504)
    }

    // MARK: - Paging

    /// The dots are centred on the row itself rather than balanced between the
    /// two buttons. The first and last pages carry only one button, and any
    /// layout that positions the dots *relative to the buttons* moves them by
    /// half a button whenever one of the ends is missing.
    private var footer: some View {
        HStack(spacing: 0) {
            if step > 0 {
                StepNavButton(direction: .back) { go(to: step - 1) }
            }

            Spacer(minLength: 24)

            if step < TutorialStep.all.count - 1 {
                StepNavButton(direction: .next) { go(to: step + 1) }
            }
        }
        .frame(height: StepNavButton.height)
        .overlay { dots }
        .padding(.horizontal, 14)
    }

    private var dots: some View {
        HStack(spacing: 8.47) {
            ForEach(TutorialStep.all.indices, id: \.self) { index in
                Circle()
                    .fill(index == step
                          ? Theme.Palette.pageIndicator
                          : Theme.Palette.pageIndicatorInactive)
                    .frame(width: 12, height: 12)
            }
        }
        .allowsHitTesting(false)
        .accessibilityElement()
        .accessibilityLabel("Step \(step + 1) of \(TutorialStep.all.count)")
    }

    private func go(to index: Int) {
        withAnimation(.snappy(duration: 0.28)) { step = index }
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
    /// Line art exported from the design, one drawing per step. Template
    /// assets, so they take the palette's white rather than carrying their own.
    let artwork: String
    let rows: [Row]

    static let all: [TutorialStep] = [
        TutorialStep(
            number: 1,
            title: "Prepare Your 2D Image",
            artwork: "TutorialPrepare",
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
            artwork: "TutorialConvert",
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
            artwork: "TutorialExport",
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

// MARK: - Page

private struct StepPage: View {
    let step: TutorialStep

    var body: some View {
        HStack(alignment: .top, spacing: 46) {
            VStack(alignment: .leading, spacing: 46) {
                Text("\(step.number). \(step.title)")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(Theme.Palette.white)

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
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(step.artwork)
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .foregroundStyle(Theme.Palette.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.Palette.white)

                Text(row.caption)
                    .font(.system(size: 14, weight: .light))
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // A floor rather than a fixed height: the longest caption still runs to
        // two lines once the column is only half the page wide.
        .frame(minHeight: 64)
        .accessibilityElement(children: .combine)
    }
}

private struct StepNavButton: View {
    enum Direction { case back, next }

    static let width: CGFloat = 82
    static let height: CGFloat = 42

    let direction: Direction
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if direction == .back {
                    Image(systemName: "chevron.backward")
                    Text("Back")
                } else {
                    Text("Next")
                    Image(systemName: "chevron.forward")
                }
            }
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(Theme.Palette.white)
            .frame(width: Self.width, height: Self.height)
            .background(Theme.Palette.controlFill,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Theme.Palette.workspaceStroke, lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview(traits: .landscapeLeft) {
    TutorialsView()
        .environment(AppState())
        .background(Theme.Palette.canvas)
        .preferredColorScheme(.dark)
}
