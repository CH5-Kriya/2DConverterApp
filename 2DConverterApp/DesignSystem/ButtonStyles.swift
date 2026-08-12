import SwiftUI

struct KriyaPrimaryButtonStyle: ButtonStyle {
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

struct KriyaSecondaryButtonStyle: ButtonStyle {
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

extension ButtonStyle where Self == KriyaPrimaryButtonStyle {
    static var kriyaPrimary: KriyaPrimaryButtonStyle { .init() }
    static func kriyaPrimary(fillsWidth: Bool) -> KriyaPrimaryButtonStyle {
        .init(fillsWidth: fillsWidth)
    }
}

extension ButtonStyle where Self == KriyaSecondaryButtonStyle {
    static var kriyaSecondary: KriyaSecondaryButtonStyle { .init() }
    static func kriyaSecondary(fillsWidth: Bool) -> KriyaSecondaryButtonStyle {
        .init(fillsWidth: fillsWidth)
    }
}
