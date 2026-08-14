import SwiftUI

struct TacturaPrimaryButtonStyle: ButtonStyle {
    var fillsWidth = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typography.button)
            .foregroundStyle(Theme.Palette.onAccent)
            .frame(maxWidth: fillsWidth ? .infinity : nil)
            .frame(width: fillsWidth ? nil : Theme.Metrics.buttonWidth,
                   height: Theme.Metrics.buttonHeight)
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

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typography.button)
            .foregroundStyle(Theme.Palette.textPrimary)
            .frame(maxWidth: fillsWidth ? .infinity : nil)
            .frame(width: fillsWidth ? nil : Theme.Metrics.buttonWidth,
                   height: Theme.Metrics.buttonHeight)
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
/// with a hairline stroke, sized to the design's 42pt control height.
struct WorkspaceChipButtonStyle: ButtonStyle {
    var width: CGFloat?

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.Metrics.workspaceControlRadius,
                         style: .continuous)
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(Theme.Palette.workspaceLabel)
            .frame(width: width, height: Theme.Metrics.workspaceControlHeight)
            .frame(minWidth: Theme.Metrics.workspaceControlHeight)
            .background(Theme.Palette.workspaceControl, in: shape)
            .overlay(shape.strokeBorder(Theme.Palette.workspaceStroke, lineWidth: 0.5))
            .opacity(configuration.isPressed ? 0.6 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// The workspace's one committing action. Blue because it is the only button on
/// the screen that produces a file rather than changing the preview.
struct TacturaAccentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(Theme.Palette.workspaceLabel)
            .frame(maxWidth: .infinity)
            .frame(height: Theme.Metrics.workspaceControlHeight)
            .background(
                Theme.Palette.action,
                in: RoundedRectangle(cornerRadius: Theme.Metrics.workspaceControlRadius,
                                     style: .continuous)
            )
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
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
