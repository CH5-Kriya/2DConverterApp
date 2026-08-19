import SwiftUI
import ReliefCore
import UniformTypeIdentifiers

/// The export dialog: the relief on the left, what to write and where on the
/// right. Presented over the workspace rather than as a page, because the
/// choice is about the thing already on screen.
struct ExportSheet: View {
    @Environment(\.dismiss) private var dismiss

    let preview: CGImage?
    let height: Plane
    let config: ReliefConfig
    /// Reported back so the project can record that it has been exported. The
    /// sheet owns the write and knows when it landed; nothing else does.
    let onExported: () -> Void

    @State private var model: ExportViewModel
    @State private var pickingFolder = false

    init(projectName: String,
         preview: CGImage?,
         height: Plane,
         config: ReliefConfig,
         relief: ReliefService,
         onExported: @escaping () -> Void = {}) {
        self.preview = preview
        self.height = height
        self.config = config
        self.onExported = onExported
        _model = State(initialValue: ExportViewModel(projectName: projectName,
                                                     relief: relief))
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.62)
                .ignoresSafeArea()
                .onTapGesture { if !model.stage.isRunning { dismiss() } }

            card
                .frame(maxWidth: 1040)
                .padding(40)

            if model.stage.isRunning {
                ExportProgressDialog(stage: model.stage) { model.cancel() }
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .animation(.snappy(duration: 0.2), value: model.stage.isRunning)
        .fileImporter(isPresented: $pickingFolder,
                      allowedContentTypes: [.folder]) { result in
            model.setDestination(result.map { $0 })
        }
        .onChange(of: model.stage) { _, stage in
            if case .finished = stage {
                onExported()
                dismiss()
            }
        }
    }

    private var card: some View {
        HStack(spacing: 0) {
            previewPane
            form
        }
        .background(Theme.Palette.surface,
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityAddTraits(.isModal)
    }

    // MARK: - Left

    private var previewPane: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Preview")
                .font(Theme.Typography.rowTitle)
                .foregroundStyle(Theme.Palette.textPrimary)

            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.Palette.canvas)
                .aspectRatio(4 / 3, contentMode: .fit)
                .overlay {
                    if let preview {
                        Image(decorative: preview, scale: 1)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 10,
                                                        style: .continuous))
                    } else {
                        Image(systemName: "cube.transparent")
                            .font(.system(size: 34, weight: .light))
                            .foregroundStyle(Theme.Palette.textTertiary)
                    }
                }

            Spacer(minLength: 0)
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.Palette.sidebar)
    }

    // MARK: - Right

    private var form: some View {
        @Bindable var model = model

        return VStack(alignment: .leading, spacing: 22) {
            Text("Export Artwork")
                .font(Theme.Typography.heading)
                .foregroundStyle(Theme.Palette.textPrimary)
                .padding(.bottom, 4)

            field("Project name") {
                TextField("Project name", text: $model.projectName)
                    .textFieldStyle(.plain)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .padding(.horizontal, 16)
                    .frame(height: 46)
                    .background(inputBackground)
            }

            field("Export location") {
                HStack(spacing: 0) {
                    Text(model.destinationLabel)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(model.destination == nil
                                         ? Theme.Palette.textTertiary
                                         : Theme.Palette.textPrimary)
                        .lineLimit(1)
                        .padding(.leading, 16)

                    Spacer(minLength: 8)

                    Button {
                        pickingFolder = true
                    } label: {
                        Image(systemName: "folder")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Theme.Palette.textPrimary)
                            .frame(width: 46, height: 46)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Choose export folder")
                }
                .frame(height: 46)
                .background(inputBackground)
            }

            field("File type") {
                // Buttons rather than a menu: with a handful of formats the
                // whole choice is worth showing at once, and the selected one
                // stays visible instead of hiding behind a tap.
                HStack(spacing: 12) {
                    ForEach(ExportFormat.allCases) { format in
                        FormatButton(format: format,
                                     isSelected: model.format == format) {
                            model.format = format
                        }
                    }
                }
            }

            if case .failed(let message) = model.stage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Color(hex: 0xE06C6C))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Button {
                model.export(height: height, config: config)
            } label: {
                Text("Export")
                    .font(Theme.Typography.button)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(Theme.Palette.action,
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!model.canExport)
            .opacity(model.canExport ? 1 : 0.45)
        }
        .padding(30)
        .frame(width: 430, alignment: .topLeading)
    }

    private var inputBackground: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Theme.Palette.canvas)
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Theme.Palette.separator, lineWidth: 1)
            }
    }

    @ViewBuilder
    private func field<Content: View>(_ label: String,
                                      @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(Theme.Palette.textSecondary)
            content()
        }
    }
}

/// One file-type choice. The selected one carries the action colour, the same
/// blue as the Export button below it — the format and the commitment are the
/// same decision, a step apart.
private struct FormatButton: View {
    let format: ExportFormat
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(format.label)
                .font(Theme.Typography.caption)
                .foregroundStyle(isSelected ? .white : Theme.Palette.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(isSelected
                            ? Theme.Palette.action
                            : Theme.Palette.surfaceSelected,
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(format.label), \(format.detail)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .animation(.easeOut(duration: 0.15), value: isSelected)
    }
}
