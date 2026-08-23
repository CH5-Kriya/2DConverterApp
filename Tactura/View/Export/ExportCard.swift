import ReliefCore
import SwiftUI
import UniformTypeIdentifiers

/// The export form, in the panel the adjustment card was in.
///
/// Not a sheet over the workspace. Choosing a file name and a folder is a
/// question about the relief already on screen, and the sheet answered it by
/// covering that relief with a smaller copy of itself — a second preview to
/// build, to keep in step, and to look at instead of the real one. Swapping the
/// card leaves the model exactly where it was, at the size it was being judged
/// at, and costs the panel nothing it was using.
///
/// The card is the form and only the form. What a run is doing, and the buttons
/// that start and leave it, belong to the panel's bottom slot — see
/// `ExportActions`, which keeps them where the adjustment card's own Export
/// button has always been.
struct ExportCard: View {
    @Bindable var model: ExportViewModel

    @State private var pickingFolder = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Export")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.Palette.textPrimary)

            field("Project name") {
                TextField("Project name", text: $model.projectName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .padding(.horizontal, 12)
                    .frame(height: Theme.Metrics.workspaceControlHeight)
                    .background(inputBackground)
                    .disabled(model.stage.isRunning)
            }

            field("Export location") {
                HStack(spacing: 0) {
                    Text(model.destinationLabel)
                        .font(.system(size: 14))
                        .foregroundStyle(model.destination == nil
                                         ? Theme.Palette.textTertiary
                                         : Theme.Palette.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(.leading, 12)

                    Spacer(minLength: 4)

                    Button {
                        pickingFolder = true
                    } label: {
                        Image(systemName: "folder")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Theme.Palette.textPrimary)
                            .frame(width: Theme.Metrics.workspaceControlHeight,
                                   height: Theme.Metrics.workspaceControlHeight)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Choose export folder")
                }
                .frame(height: Theme.Metrics.workspaceControlHeight)
                .background(inputBackground)
            }

            field("File type") {
                // Both formats at once rather than behind a menu: there are two
                // of them, and the one in force stays readable while the rest
                // of the form is filled in.
                HStack(spacing: 10) {
                    ForEach(ExportFormat.allCases) { format in
                        FormatChip(format: format,
                                   isSelected: model.format == format) {
                            model.format = format
                        }
                    }
                }
            }
        }
        .padding(24)
        .frame(width: Theme.Metrics.workspacePanelWidth, alignment: .leading)
        .background(Theme.Palette.workspacePanel,
                    in: RoundedRectangle(cornerRadius: Theme.Metrics.workspacePanelRadius,
                                         style: .continuous))
        .fileImporter(isPresented: $pickingFolder,
                      allowedContentTypes: [.folder]) { result in
            model.setDestination(result.map { $0 })
        }
    }

    private var inputBackground: some View {
        RoundedRectangle(cornerRadius: Theme.Metrics.workspaceControlRadius,
                         style: .continuous)
            .fill(Theme.Palette.workspaceControl)
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Metrics.workspaceControlRadius,
                                 style: .continuous)
                    .strokeBorder(Theme.Palette.workspaceStroke, lineWidth: 0.3)
            }
    }

    @ViewBuilder
    private func field<Content: View>(_ label: String,
                                      @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(Theme.Palette.textSecondary)
            content()
        }
    }
}

/// The panel's bottom slot while the export form is up.
///
/// Cancel takes the place the adjustment card's Export button occupies, and
/// Export moves one row above it. Both cards therefore end in a full-width
/// button at the same height, and the one directly under the card is always the
/// one that leaves the mode you are in — the placement carries the meaning, so
/// neither has to be hunted for after the swap.
struct ExportActions: View {
    @Bindable var model: ExportViewModel

    /// Captured by the panel as the actions are built, so the file that gets
    /// written is the surface on screen rather than whatever the sliders reach
    /// afterwards.
    let height: Plane
    let config: ReliefConfig

    /// Back to the adjustment card. Distinct from cancelling a *run*, which is
    /// what the same button does while one is in flight — see `cancel`.
    let onClose: () -> Void
    let onFinished: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            if case .failed(let message) = model.stage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(hex: 0xE06C6C))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if model.stage.isRunning { running }

            Button("Export") {
                model.export(height: height, config: config)
            }
            .buttonStyle(.tacturaAccent)
            .disabled(!model.canExport)
            .opacity(model.canExport ? 1 : 0.45)

            Button(action: cancel) {
                Text("Cancel").frame(maxWidth: .infinity)
            }
            .buttonStyle(.workspaceChip)
        }
        .onChange(of: model.stage) { _, stage in
            if case .finished = stage { onFinished() }
        }
    }

    /// The wait, in the panel rather than over the workspace. The relief stays
    /// visible while the file is written, which is the whole reason the form
    /// moved here.
    private var running: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProgressView(value: fraction)
                .tint(Theme.Palette.action)

            HStack(spacing: 8) {
                // The remaining line is derived from elapsed wall clock, so it
                // needs a heartbeat. `TimelineView` gives one without pulling in
                // Combine, which this app deliberately avoids.
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    // The phase until the rate is measurable, the countdown
                    // after — never a number invented before there is anything
                    // to measure.
                    Text(model.stage.remaining?.remainingPhrase ?? phase)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Text("\(Int(fraction * 100))%")
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Exporting. \(phase). \(Int(fraction * 100)) percent")
    }

    private var fraction: Double {
        if case .running(let value, _, _) = model.stage { return value }
        return 0
    }

    private var phase: String {
        if case .running(_, let label, _) = model.stage { return label }
        return ""
    }

    /// One button, two jobs, in the order a person means them: stop the run if
    /// one is going, otherwise put the adjustment card back. Never both — a
    /// Cancel that also closed would throw away the half-filled form on the way
    /// out of a run that was only meant to be stopped.
    private func cancel() {
        if model.stage.isRunning {
            model.cancel()
        } else {
            onClose()
        }
    }
}

/// One file-type choice, sized for the workspace panel rather than the sheet's
/// wider form. The selected one carries the action colour — the same blue as
/// Export beneath it, because the format and the commitment are one decision a
/// step apart.
private struct FormatChip: View {
    let format: ExportFormat
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(format.label)
                .font(.system(size: 14))
                .foregroundStyle(isSelected ? .white : Theme.Palette.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: Theme.Metrics.workspaceControlHeight)
                .background(isSelected
                            ? Theme.Palette.action
                            : Theme.Palette.surfaceSelected,
                            in: RoundedRectangle(
                                cornerRadius: Theme.Metrics.workspaceControlRadius,
                                style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(format.label), \(format.detail)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .animation(.easeOut(duration: 0.15), value: isSelected)
    }
}
