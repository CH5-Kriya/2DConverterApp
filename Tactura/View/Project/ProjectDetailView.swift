import ReliefCore
import SwiftUI

/// The editing workspace: the converted relief in 3D, with the parameters that
/// shape it alongside. The whole screen exists so the two can be read together —
/// a slider whose effect you can't see is just a number.
struct ProjectDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: ProjectDetailViewModel

    /// The export run, and the panel's mode: while this exists the card on the
    /// right is the export form rather than the sliders. One piece of state for
    /// both, so the form cannot outlive the run or the run the form.
    @State private var export: ExportViewModel?

    /// App-wide and `@AppStorage` rather than per-project state: how much of
    /// the panel someone wants to see is a fact about them, not about the
    /// relief they happen to have open. Simple by default — Advanced is
    /// something you go and ask for.
    @AppStorage("reliefConfigurationMode")
    private var mode: ProjectDetailViewModel.ConfigurationMode = .simple
    @State private var isRenaming = false
    @State private var draftName = ""
    @State private var isShowingSourceImage = false

    /// The workspace comes from the store rather than being built here: this
    /// view is recreated on every push, and a workspace built with it would
    /// arrive with no checkpoint and no conversion in flight.
    init(projectID: UUID, dependencies: AppDependencies) {
        _model = State(initialValue: dependencies.workspaces.workspace(for: projectID))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            content
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Palette.workspaceCanvas)
        .overlay {
            if isShowingSourceImage, let image = model.sourceImage {
                SourceImagePopup(image: image) {
                    withAnimation(.snappy(duration: 0.22)) { isShowingSourceImage = false }
                }
                .transition(.opacity)
            }
        }
        .task { await model.load() }
        .toolbar(.hidden, for: .navigationBar)
        .alert("Rename Project", isPresented: $isRenaming) {
            TextField("Name", text: $draftName)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                Task { await model.rename(to: draftName) }
            }
            .disabled(draftName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    // MARK: - Header

    private var header: some View {
        ZStack {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Label("Back", systemImage: "chevron.backward")
                        .labelStyle(.titleAndIcon)
                        .padding(.horizontal, 12)
                }
                .buttonStyle(.workspaceChip)
                Spacer()
            }

            Button {
                draftName = model.project?.name ?? ""
                isRenaming = true
            } label: {
                HStack(spacing: 8) {
                    Text(model.project?.name ?? "Project")
                        .font(.system(size: 24))
                        .underline()
                        .foregroundStyle(Theme.Palette.workspaceLabel.opacity(0.9))
                    Image("RenameProject")
                        .resizable()
                        .renderingMode(.template)
                        .frame(width: 18, height: 18)
                        .foregroundStyle(Theme.Palette.workspaceLabel.opacity(0.9))
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Rename project")
        }
        .frame(height: Theme.Metrics.workspaceControlHeight)
    }

    // MARK: - Body

    private var content: some View {
        HStack(alignment: .bottom, spacing: 24) {
            VStack(spacing: 16) {
                viewport
                HStack {
                    Spacer()
                    historyControls
                }
            }

            VStack(spacing: 0) {
                sourceThumbnail
                Spacer(minLength: 0)
                panelCard
                Spacer(minLength: 0)
                panelActions
            }
            .frame(width: Theme.Metrics.workspacePanelWidth)
            // Clipped to the panel so the card sliding in from the right is
            // never drawn over the viewport beside it.
            .clipped()
            .animation(.easeInOut(duration: 0.24), value: isExporting)
        }
        .padding(.top, 16)
    }

    /// Sits above the panel and only when there is a photograph to show: a
    /// project opened from a checkpoint whose import has since gone from the
    /// store gets the panel where it has always been, not an empty plate.
    @ViewBuilder
    private var sourceThumbnail: some View {
        if let image = model.sourceImage {
            SourceImageThumbnail(image: image) {
                withAnimation(.snappy(duration: 0.22)) { isShowingSourceImage = true }
            }
        }
    }

    /// One state at a time. The 3D view renders whatever mesh it is given and
    /// nothing else, so the screen — which is the only thing that knows why
    /// there is no mesh — owns every empty and in-flight state.
    @ViewBuilder
    private var viewport: some View {
        switch model.stage {
        // A workspace outlives the screen now, so a failure that used to be
        // retried by walking out and back in would otherwise stick for the rest
        // of the session. The way back has to be on the screen.
        case .failed(let message):
            VStack(spacing: 20) {
                EmptyStateView(systemImage: "exclamationmark.triangle",
                               title: "Conversion failed",
                               message: message)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Try again") { model.convert() }
                    .buttonStyle(.workspaceChip)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        // Until `load()` returns there is no project, let alone a mesh, and an
        // empty 3D canvas is indistinguishable from a black screen. Short —
        // one file read — but it is the first thing the workspace shows, and
        // the push has already put it on screen by then.
        case .idle where model.isLoading:
            ProgressView()
                .controlSize(.large)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .idle where model.project?.hasSourceImage == false:
            EmptyStateView(systemImage: "photo.badge.plus",
                           title: "No source image",
                           message: "This project has no photo to convert.")

        case .converting(let label, let fraction):
            Relief3DPreview(mesh: model.previewMesh)
                .overlay { progress(label: label, fraction: fraction) }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .idle, .ready:
            Relief3DPreview(mesh: model.previewMesh)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay { refining }
                .overlay(alignment: .bottom) { saveBadge }
                .animation(.easeOut(duration: 0.18), value: model.refiningLabel)
                .animation(.easeOut(duration: 0.18), value: model.saveState)
                .animation(.easeOut(duration: 0.18), value: model.notice)
        }
    }

    /// A slider move re-blends at `work_res` and rebuilds the preview mesh,
    /// which is a second or two of work. Without this the relief simply
    /// changed under the person's hand with no sign the app was still on it.
    ///
    /// The veil is doing two jobs. It says the app is still working, and it
    /// puts the stale surface out of reach — what is on screen during a
    /// re-blend answers to the *previous* slider positions, so inviting someone
    /// to orbit and judge it is inviting them to judge the wrong shape.
    ///
    /// Indeterminate rather than a fraction: the blend reports no progress of
    /// its own, and a bar that crawls to a number the pipeline never sent is a
    /// lie told smoothly.
    @ViewBuilder
    private var refining: some View {
        if let label = model.refiningLabel {
            ZStack {
                // Material rather than `.blur` on the preview itself. Putting a
                // filter on a RealityView forces its Metal layer through an
                // offscreen pass, and this screen already has a documented
                // history of exhausting the drawable pool that way — see
                // `ReliefStage.frame(_:)`. A backdrop reads the composited
                // result instead and costs the preview nothing.
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(Theme.Palette.canvas.opacity(0.45))

                VStack(spacing: 14) {
                    Text(label)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.textSecondary)
                    IndeterminateBar()
                    autosaveNote
                }
                .padding(28)
                .background(Theme.Palette.workspacePanel.opacity(0.86),
                            in: RoundedRectangle(cornerRadius: Theme.Metrics.workspacePanelRadius,
                                                 style: .continuous))
            }
            .transition(.opacity)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(label). Updating the preview. \(model.saveState.note)")
        }
    }

    /// Inside the card rather than as a badge of its own, because during a
    /// re-blend the two facts belong together: the preview is catching up, and
    /// the setting that changed it is already on disk.
    private var autosaveNote: some View {
        Label {
            Text(model.saveState.note)
        } icon: {
            Image(systemName: model.saveState == .saving
                  ? "arrow.triangle.2.circlepath"
                  : "checkmark.circle.fill")
        }
        .font(.system(size: 12))
        .foregroundStyle(Theme.Palette.textTertiary)
        .padding(.top, 2)
    }

    /// The same reassurance when there is no card to put it in — after a
    /// conversion, whose checkpoint is the largest thing the app writes, and
    /// after an edit whose re-blend has already finished. Fades on its own:
    /// a permanent "Saved" stops being information after the first time.
    /// Finishing an export takes this slot ahead of the save badge. The two
    /// cannot both be the most important thing at once, and the write that
    /// follows an export would otherwise put "Saved" over the news that the
    /// file the person actually asked for is on disk.
    @ViewBuilder
    private var saveBadge: some View {
        if let notice = model.notice {
            badge(notice, systemImage: "checkmark.circle.fill", label: notice)
        } else if !model.isRefining, model.saveState != .idle {
            badge(model.saveState == .saving ? "Saving" : "Saved",
                  systemImage: model.saveState == .saving
                               ? "arrow.triangle.2.circlepath"
                               : "checkmark.circle.fill",
                  label: model.saveState.note)
        }
    }

    private func badge(_ text: String,
                       systemImage: String,
                       label: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(Theme.Typography.caption)
            .foregroundStyle(Theme.Palette.textSecondary)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(Theme.Palette.workspacePanel.opacity(0.86),
                        in: Capsule(style: .continuous))
            .padding(.bottom, 20)
            .transition(.opacity.combined(with: .offset(y: 10)))
            .accessibilityElement(children: .combine)
            .accessibilityLabel(label)
    }

    /// The conversion's wait, told the way the export's is: a bar, what is left
    /// of it, and how far along it is.
    ///
    /// It used to be a phase and a bare bar. That was honest but thin — this is
    /// the longest wait in the app by a wide margin, minutes rather than
    /// seconds, and a bar with no number beside it gives someone nothing to
    /// decide whether to sit through it. The estimate is the same
    /// extrapolation the export runs on, so the two waits read alike.
    private func progress(label: String, fraction: Double) -> some View {
        VStack(spacing: 24) {
            Text(label)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.textSecondary)

            VStack(alignment: .leading, spacing: 10) {
                ProgressView(value: fraction)
                    .tint(Theme.Palette.action)

                // Both halves read the wall clock, so both need the heartbeat —
                // the same one the export's row runs on.
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    HStack(spacing: 8) {
                        Text(model.conversionElapsed)
                            .monospacedDigit()

                        Spacer(minLength: 0)

                        // Nothing until there is a rate worth extrapolating
                        // from. The slot keeps its name either way, so the
                        // number arriving does not read as a new field.
                        Text(model.conversionRemaining?.estimatePhrase
                             ?? "Estimated Time: calculating")
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .lineLimit(1)
                }
            }
            // The width the design gives this card: 577 pt of content inside
            // 28 pt sides. Wider than the export's, which has only the panel's
            // 238 pt to live in.
            .frame(width: 577)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
        .background(Theme.Palette.workspacePanel.opacity(0.86),
                    in: RoundedRectangle(cornerRadius: Theme.Metrics.workspacePanelRadius,
                                         style: .continuous))
        .accessibilityElement(children: .combine)
        // The percentage left the row when the design's clock took its side,
        // but "halfway" is the cheapest thing to say and the hardest to read
        // off a bar you cannot see, so VoiceOver keeps it.
        .accessibilityLabel(
            "\(label). \(Int(fraction * 100)) percent."
            + (model.conversionRemaining.map { " \($0.remainingPhrase)." } ?? ""))
    }

    private var historyControls: some View {
        HStack(spacing: 12) {
            Button {
                model.undo()
            } label: {
                Image(systemName: "arrow.uturn.left")
            }
            .buttonStyle(.workspaceChip)
            .disabled(!model.canUndo)
            .accessibilityLabel("Undo")

            Button {
                model.redo()
            } label: {
                Image(systemName: "arrow.uturn.right")
            }
            .buttonStyle(.workspaceChip)
            .disabled(!model.canRedo)
            .accessibilityLabel("Redo")
        }
        .opacity(model.canRefine ? 1 : 0.35)
    }

    /// True only when there is both a run to show and a surface to write, which
    /// is what `panelCard` and `panelActions` both key off: the card and the
    /// buttons beneath it can then never disagree about which mode the panel is
    /// in.
    private var isExporting: Bool { export != nil && model.height != nil }

    @ViewBuilder
    private var panelCard: some View {
        // A push, not a cross-fade: the export form arrives from the right and
        // the settings leave to the left, so the panel reads as moving forward
        // a step rather than swapping its contents in place. Cancelling runs it
        // backwards.
        if let export, isExporting {
            ExportCard(model: export)
                .transition(.move(edge: .trailing).combined(with: .opacity))
        } else {
            configurationPanel
                .transition(.move(edge: .leading).combined(with: .opacity))
        }
    }

    /// The panel's bottom slot. Export sits where it always has until the form
    /// is up, at which point Cancel takes that place and Export moves one row
    /// above it — so the button directly under the card is always the one that
    /// leaves the mode.
    @ViewBuilder
    private var panelActions: some View {
        if let export, let height = model.height, isExporting {
            ExportActions(model: export,
                          height: height,
                          config: model.currentConfig(),
                          onClose: { self.export = nil },
                          onFinished: {
                              Task { await model.markExported() }
                              self.export = nil
                          })
        } else {
            exportButton
        }
    }

    // MARK: - Configuration

    private var configurationPanel: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 16) {
                sectionTitle("Mode")
                Picker("Mode", selection: $mode) {
                    ForEach(ProjectDetailViewModel.ConfigurationMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 16) {
                sectionTitle("Configuration")
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(ProjectDetailViewModel.Control.shown(in: mode)) { control in
                        parameterRow(control)
                    }
                    hiddenSettingsNote
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: mode)
        .padding(24)
        .frame(width: Theme.Metrics.workspacePanelWidth, alignment: .leading)
        .background(Theme.Palette.workspacePanel,
                    in: RoundedRectangle(cornerRadius: Theme.Metrics.workspacePanelRadius,
                                         style: .continuous))
        .disabled(!model.canRefine)
        .opacity(model.canRefine ? 1 : 0.5)
    }

    /// Simple hides two sliders; it does not neutralise them. When one of them
    /// is off its default the shape on screen has an input the panel isn't
    /// showing, and saying so is cheaper than letting it read as a bug.
    @ViewBuilder
    private var hiddenSettingsNote: some View {
        let hidden = model.advancedEditCount
        if mode == .simple && hidden > 0 {
            Text(hidden == 1 ? "1 advanced setting in use"
                             : "\(hidden) advanced settings in use")
                .font(.system(size: 12))
                .foregroundStyle(Theme.Palette.textTertiary)
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Theme.Palette.textPrimary)
    }

    private func parameterRow(_ control: ProjectDetailViewModel.Control) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(control.title)
                .font(.system(size: 14))
                .foregroundStyle(Theme.Palette.textPrimary)

            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 3) {
                    Slider(value: binding(for: control), in: 0...1) { editing in
                        // One drag is one edit. Committing per touch event would
                        // fill the undo stack with sixty steps nobody asked for,
                        // and re-blend on every one of them.
                        if !editing { model.commit() }
                    }
                    .tint(Theme.Palette.accentFill)
                    .accessibilityHint("Default \(model.defaultReadout(for: control))")

                    defaultMark(for: control)
                }

                Text(model.readout(for: control))
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .frame(width: 56, height: 30)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(Theme.Palette.workspaceStroke, lineWidth: 0.3)
                    )
            }
        }
    }

    /// The default, marked under the track.
    ///
    /// A slider says where the value is; it does not say whether that is more
    /// or less than the pipeline's own setting, and none of these four default
    /// to the middle of their range — Outline defaults to the top of its. The
    /// mark is what makes "deeper than usual" readable without having to
    /// remember that usual is 30 mm.
    private func defaultMark(for control: ProjectDetailViewModel.Control) -> some View {
        GeometryReader { proxy in
            // The thumb's centre travels between half a thumb from each end of
            // the track, so the mark follows that span rather than the full
            // width. At the ends — where Outline's default sits — placing it at
            // a plain fraction of the width would miss by the whole 14 pt.
            let travel = max(proxy.size.width - Self.sliderThumb, 0)
            UpTriangle()
                .fill(Theme.Palette.textTertiary)
                .frame(width: Self.markWidth, height: Self.markHeight)
                .offset(x: Self.sliderThumb / 2
                           + travel * model.defaultValue(for: control)
                           - Self.markWidth / 2)
        }
        .frame(height: Self.markHeight)
        // The slider carries the same fact as a hint, spelled in the readout's
        // own units, so nothing here is only available to people who can see it.
        .accessibilityHidden(true)
    }

    /// The slider thumb, measured rather than assumed: iOS 26 draws it as a
    /// 36 pt capsule, not the 28 pt circle it used to be. Getting this wrong
    /// tilts every mark outward from the centre — at 28 the mark for a default
    /// of 1.0 sat 4 pt past the thumb it was pointing at.
    private static let sliderThumb: CGFloat = 36
    private static let markWidth: CGFloat = 7
    private static let markHeight: CGFloat = 5

    /// Hands the panel over to the export form rather than writing a file
    /// here. Choosing the format and the destination is a handful of fields,
    /// not a screen of its own, and they ask about the relief already on
    /// display — so they take the card beside it instead of covering it.
    private var exportButton: some View {
        VStack(spacing: 12) {
            Button("Export") {
                guard model.height != nil else { return }
                export = ExportViewModel(projectName: model.project?.name ?? "relief",
                                         relief: model.relief)
            }
                .buttonStyle(.tacturaAccent)
                // Disabled mid-refine, not merely discouraged: the height field
                // on hand is still the previous edit's, and exporting it would
                // write a file that does not match the preview.
                .disabled(!model.canRefine || model.isRefining)
                .opacity(model.canRefine && !model.isRefining ? 1 : 0.5)

            // Holds the row Cancel takes once the form is open, so Export never
            // moves between the two modes. It is the real button, hidden,
            // rather than a spacer of a guessed height that could drift from it.
            Button(action: {}) {
                Text("Cancel").frame(maxWidth: .infinity)
            }
            .buttonStyle(.workspaceChip)
            .hidden()
            .accessibilityHidden(true)
        }
    }

    // MARK: - Bindings

    private func binding(for control: ProjectDetailViewModel.Control) -> Binding<Double> {
        Binding { model.value(for: control) } set: { model.setValue($0, for: control) }
    }
}

/// The mark under a slider's track. Drawn rather than borrowed from SF Symbols:
/// `arrowtriangle.up.fill` carries its own padding inside the glyph, so at five
/// points the tip would not land on the value it points at.
private struct UpTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// A bar that moves while something with no measurable progress is happening.
///
/// Not `ProgressView()`. Indeterminate is a spinner on iOS, and forcing
/// `.progressViewStyle(.linear)` on it draws a track that never animates —
/// three screenshots a second apart came back byte-identical. A still bar is
/// worse than no bar: it reads as the app having stopped, which is the exact
/// impression this overlay exists to prevent.
private struct IndeterminateBar: View {
    var width: CGFloat = 220
    var height: CGFloat = 5

    @State private var sliding = false

    var body: some View {
        Capsule(style: .continuous)
            .fill(Theme.Palette.accentFill.opacity(0.16))
            .frame(width: width, height: height)
            .overlay(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Theme.Palette.accentFill)
                    .frame(width: width * 0.34)
                    .offset(x: sliding ? width * 0.66 : 0)
            }
            .clipShape(Capsule(style: .continuous))
            .onAppear {
                withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
                    sliding = true
                }
            }
            // The phase label above it already says what is happening; a second
            // voice reading a bar with no value adds nothing.
            .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview(traits: .landscapeLeft) {
    ProjectDetailView(projectID: Project.previewSamples[0].id, dependencies: .preview)
        .preferredColorScheme(.dark)
}
#endif
