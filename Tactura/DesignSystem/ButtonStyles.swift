import SwiftUI

private struct TacturaCanvasScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}

extension EnvironmentValues {
    var tacturaCanvasScale: CGFloat {
        get { self[TacturaCanvasScaleKey.self] }
        set { self[TacturaCanvasScaleKey.self] = newValue }
    }
}

private let minimumTapTarget: CGFloat = 44

private func rendered(_ points: CGFloat, at scale: CGFloat) -> CGFloat {
    points / max(scale, 0.01)
}

private struct TacturaControlFrame: ViewModifier {
    @Environment(\.tacturaCanvasScale) private var canvasScale

    let width: CGFloat?
    let height: CGFloat?
    let minimumRenderedSize: CGFloat

    func body(content: Content) -> some View {
        let minimum = rendered(minimumRenderedSize, at: canvasScale)
        content.frame(width: width.map { max($0, minimum) },
                      height: height.map { max($0, minimum) })
    }
}

private struct TacturaButtonFont: ViewModifier {
    @Environment(\.tacturaCanvasScale) private var canvasScale

    let size: CGFloat
    let weight: Font.Weight
    let minimumRenderedSize: CGFloat

    func body(content: Content) -> some View {
        content.font(.system(size: max(size,
                                      rendered(minimumRenderedSize,
                                               at: canvasScale)),
                                  weight: weight))
    }
}

extension View {
    /// Keeps a control at Apple's 44 pt minimum after `DesignCanvas` scales it.
    func tacturaControlFrame(width: CGFloat? = nil,
                             height: CGFloat? = nil,
                             minimumRenderedSize: CGFloat = minimumTapTarget) -> some View {
        modifier(TacturaControlFrame(width: width,
                                     height: height,
                                     minimumRenderedSize: minimumRenderedSize))
    }

    func tacturaButtonFont(size: CGFloat,
                           weight: Font.Weight = .regular,
                           minimumRenderedSize: CGFloat = 17) -> some View {
        modifier(TacturaButtonFont(size: size,
                                   weight: weight,
                                   minimumRenderedSize: minimumRenderedSize))
    }
}

struct TacturaPrimaryButtonStyle: ButtonStyle {
    var fillsWidth = false
    @Environment(\.tacturaCanvasScale) private var canvasScale

    func makeBody(configuration: Configuration) -> some View {
        let height = max(Theme.Metrics.buttonHeight,
                         rendered(minimumTapTarget, at: canvasScale))
        let width = max(Theme.Metrics.buttonWidth,
                        rendered(160, at: canvasScale))
        let fontSize = max(21, rendered(17, at: canvasScale))

        configuration.label
            .font(.system(size: fontSize, weight: .semibold))
            .foregroundStyle(Theme.Palette.onAccent)
            .frame(maxWidth: fillsWidth ? .infinity : nil)
            .frame(width: fillsWidth ? nil : width, height: height)
            .background(
                Theme.Palette.accentFill,
                in: RoundedRectangle(cornerRadius: Theme.Metrics.buttonRadius,
                                     style: .continuous)
            )
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct TacturaSecondaryButtonStyle: ButtonStyle {
    var fillsWidth = false
    @Environment(\.tacturaCanvasScale) private var canvasScale

    func makeBody(configuration: Configuration) -> some View {
        let height = max(Theme.Metrics.buttonHeight,
                         rendered(minimumTapTarget, at: canvasScale))
        let width = max(Theme.Metrics.buttonWidth,
                        rendered(160, at: canvasScale))
        let fontSize = max(21, rendered(17, at: canvasScale))

        configuration.label
            .font(.system(size: fontSize, weight: .semibold))
            .foregroundStyle(Theme.Palette.textPrimary)
            .frame(maxWidth: fillsWidth ? .infinity : nil)
            .frame(width: fillsWidth ? nil : width, height: height)
            .background(
                RoundedRectangle(cornerRadius: Theme.Metrics.buttonRadius,
                                 style: .continuous)
                    .strokeBorder(Theme.Palette.border, lineWidth: 1.5)
            )
            .opacity(configuration.isPressed ? 0.6 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// The editing workspace's chrome buttons — back, undo, redo: a near-black chip
/// with a hairline stroke. The 42 pt design height becomes 44 pt where needed.
struct WorkspaceChipButtonStyle: ButtonStyle {
    var width: CGFloat?
    @Environment(\.tacturaCanvasScale) private var canvasScale

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.Metrics.workspaceControlRadius,
                         style: .continuous)
    }

    func makeBody(configuration: Configuration) -> some View {
        let minimum = rendered(minimumTapTarget, at: canvasScale)
        let height = max(Theme.Metrics.workspaceControlHeight, minimum)
        let fontSize = max(16, rendered(17, at: canvasScale))

        configuration.label
            .font(.system(size: fontSize, weight: .medium))
            .foregroundStyle(Theme.Palette.workspaceLabel)
            .frame(width: width.map { max($0, minimum) }, height: height)
            .frame(minWidth: minimum)
            .background(Theme.Palette.workspaceControl, in: shape)
            .overlay(shape.strokeBorder(Theme.Palette.workspaceStroke, lineWidth: 0.5))
            .opacity(configuration.isPressed ? 0.6 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// The workspace's one committing action. Blue because it is the only button on
/// the screen that produces a file rather than changing the preview.
struct TacturaAccentButtonStyle: ButtonStyle {
    @Environment(\.tacturaCanvasScale) private var canvasScale

    func makeBody(configuration: Configuration) -> some View {
        let height = max(Theme.Metrics.workspaceControlHeight,
                         rendered(minimumTapTarget, at: canvasScale))
        let fontSize = max(16, rendered(17, at: canvasScale))

        configuration.label
            .font(.system(size: fontSize, weight: .medium))
            .foregroundStyle(Theme.Palette.workspaceLabel)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(
                Theme.Palette.action,
                in: RoundedRectangle(cornerRadius: Theme.Metrics.workspaceControlRadius,
                                     style: .continuous)
            )
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Plain appearance with a real touch target and a visible pressed state.
struct TacturaPlainButtonStyle: ButtonStyle {
    @Environment(\.tacturaCanvasScale) private var canvasScale

    func makeBody(configuration: Configuration) -> some View {
        let minimum = rendered(minimumTapTarget, at: canvasScale)
        configuration.label
            .frame(minWidth: minimum, minHeight: minimum)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.65 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct TacturaCircleButtonStyle: ButtonStyle {
    @Environment(\.tacturaCanvasScale) private var canvasScale

    func makeBody(configuration: Configuration) -> some View {
        let size = rendered(minimumTapTarget, at: canvasScale)
        let fontSize = max(18, rendered(17, at: canvasScale))
        configuration.label
            .font(.system(size: fontSize, weight: .medium))
            .frame(width: size, height: size)
            .background(Theme.Palette.workspaceControl, in: Circle())
            .opacity(configuration.isPressed ? 0.65 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == TacturaPlainButtonStyle {
    static var tacturaPlain: TacturaPlainButtonStyle { .init() }
}

extension ButtonStyle where Self == TacturaCircleButtonStyle {
    static var tacturaCircle: TacturaCircleButtonStyle { .init() }
}

extension ButtonStyle where Self == WorkspaceChipButtonStyle {
    static var workspaceChip: WorkspaceChipButtonStyle { .init() }
    static func workspaceChip(width: CGFloat) -> WorkspaceChipButtonStyle {
        .init(width: width)
    }
}

extension ButtonStyle where Self == TacturaAccentButtonStyle {
    static var tacturaAccent: TacturaAccentButtonStyle { .init() }
}

extension ButtonStyle where Self == TacturaPrimaryButtonStyle {
    static var tacturaPrimary: TacturaPrimaryButtonStyle { .init() }
    static func tacturaPrimary(fillsWidth: Bool) -> TacturaPrimaryButtonStyle {
        .init(fillsWidth: fillsWidth)
    }
}

extension ButtonStyle where Self == TacturaSecondaryButtonStyle {
    static var tacturaSecondary: TacturaSecondaryButtonStyle { .init() }
    static func tacturaSecondary(fillsWidth: Bool) -> TacturaSecondaryButtonStyle {
        .init(fillsWidth: fillsWidth)
    }
}
