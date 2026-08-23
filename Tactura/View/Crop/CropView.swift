import SwiftUI

/// Sits between importing a photograph and converting it.
///
/// Placed here rather than after conversion because the pipeline resamples to
/// `work_res` on the long edge: every pixel spent on a gallery wall or a picture
/// frame is detail the relief never receives. Cropping afterwards would be too
/// late to buy any of it back.
struct CropView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var model: CropViewModel
    @State private var widthField = ""
    @State private var heightField = ""

    init(projectID: UUID, dependencies: AppDependencies) {
        _model = State(initialValue: CropViewModel(projectID: projectID,
                                                   dependencies: dependencies))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            // Takes the rest of the page: without this the canvas collapses to
            // the image's ideal height and the crop area becomes a letterbox.
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Palette.canvas)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await model.load()
            syncFields()
        }
        .onChange(of: model.crop) { _, _ in syncFields() }
    }

    // MARK: Header

    private var header: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 8) {
                Text("Crop Image")
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Palette.textPrimary)
                Text("Review your image before customizing or exporting")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            .frame(maxWidth: .infinity)

            HStack {
                Button { dismiss() } label: {
                    Label("Back", systemImage: "chevron.left")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Theme.Palette.onAccent)
                        .padding(.horizontal, 18)
                        .frame(height: 46)
                        .background(Theme.Palette.accentFill,
                                    in: Capsule())
                }
                .buttonStyle(.plain)
                Spacer()
            }
        }
        .padding(.horizontal, 40)
        .padding(.top, 32)
    }

    // MARK: Body

    @ViewBuilder
    private var content: some View {
        if model.isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let image = model.image {
            // Side by side when there is room, stacked when there is not.
            // The mock is landscape; in portrait the 330 pt panel would leave
            // the image about 84 pt wide, which is not a crop tool.
            GeometryReader { proxy in
                let sideBySide = proxy.size.width >= 760

                if sideBySide {
                    HStack(alignment: .top, spacing: 40) {
                        canvas(image)
                        sidePanel
                    }
                } else {
                    VStack(spacing: 28) {
                        canvas(image)
                        sidePanel
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            EmptyStateView(systemImage: "photo.badge.exclamationmark",
                           title: "Nothing to crop",
                           message: model.errorMessage ?? "This project has no image.")
        }
    }

    private func canvas(_ image: UIImage) -> some View {
        @Bindable var model = model

        return Image(uiImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .overlay {
                CropOverlay(crop: $model.crop,
                            aspectRatio: model.aspect.ratio(
                                originalAspect: model.originalAspect))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(24)
            .background(Theme.Palette.surface,
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: Side panel

    private var sidePanel: some View {
        @Bindable var model = model

        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                Text("Crop Rectangle")
                    .font(Theme.Typography.rowTitle)
                    .foregroundStyle(Theme.Palette.textPrimary)

                HStack(spacing: 14) {
                    numberField("Width", text: $widthField) { model.setWidth($0) }
                    numberField("Height", text: $heightField) { model.setHeight($0) }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Aspect Ratio")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.Palette.textSecondary)

                    Menu {
                        Picker("Aspect Ratio", selection: $model.aspect) {
                            ForEach(CropAspect.allCases) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.inline)
                    } label: {
                        HStack {
                            Text(model.aspect.label)
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Palette.textPrimary)
                            Spacer()
                            Image(systemName: "chevron.down")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Theme.Palette.textSecondary)
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 46)
                        .background(inputBackground)
                    }
                }

                Button { model.reset() } label: {
                    Text("Reset")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.onAccent)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Theme.Palette.accentFill,
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(model.isUntouched)
                .opacity(model.isUntouched ? 0.45 : 1)
                .padding(.top, 6)
            }
            .padding(24)
            .background(Theme.Palette.sidebar,
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            Button {
                Task {
                    if let id = await model.commit() {
                        appState.open(.project(id), in: .myScans)
                    }
                }
            } label: {
                Text("Continue")
                    .font(Theme.Typography.button)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(Theme.Palette.action,
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.top, 20)
        }
        .frame(maxWidth: 330)
    }

    @ViewBuilder
    private func numberField(_ label: String, text: Binding<String>,
                             commit: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(Theme.Palette.textSecondary)
            TextField(label, text: text)
                .textFieldStyle(.plain)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.textPrimary)
                .keyboardType(.numberPad)
                .onSubmit { commit(text.wrappedValue) }
                .padding(.horizontal, 14)
                .frame(height: 46)
                .background(inputBackground)
        }
    }

    private var inputBackground: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Theme.Palette.canvas)
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Theme.Palette.separator, lineWidth: 1)
            }
    }

    private func syncFields() {
        widthField = model.widthText
        heightField = model.heightText
    }
}
