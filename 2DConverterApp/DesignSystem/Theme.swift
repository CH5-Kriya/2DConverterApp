import SwiftUI

enum Theme {

    enum Palette {
        static let canvas = Color(hex: 0x0A0A0A)
        static let sidebar = Color(hex: 0x141414)
        static let surface = Color(hex: 0x1C1C1C)
        static let surfaceSelected = Color(hex: 0x2C2C2C)
        static let separator = Color.white.opacity(0.08)
        static let border = Color.white.opacity(0.35)

        static let textPrimary = Color.white
        static let textSecondary = Color(hex: 0xA3A3A3)
        static let textTertiary = Color(hex: 0x6B6B6B)

        static let accentFill = Color(hex: 0xF5F5F5)
        static let onAccent = Color(hex: 0x0A0A0A)

        /// The one saturated colour in the palette, reserved for committing to
        /// something — exporting, and the progress of an export. Everything
        /// else in this app is greyscale on purpose, so a blue button reads as
        /// "this is the action" without any other emphasis.
        static let action = Color(hex: 0x0A84FF)
    }

    enum Metrics {
        static let sidebarWidth: CGFloat = 300
        static let sidebarRailWidth: CGFloat = 140
        static let sidebarRowHeight: CGFloat = 60
        static let sidebarRailItemSize: CGFloat = 68
        static let sidebarRowRadius: CGFloat = 14

        static let contentPadding: CGFloat = 64
        static let cardRadius: CGFloat = 18
        static let buttonRadius: CGFloat = 14
        static let buttonHeight: CGFloat = 68
        static let buttonWidth: CGFloat = 320

        static let sidebarAnimation: Animation = .snappy(duration: 0.28)
    }

    enum Typography {
        static let display = Font.system(size: 56, weight: .bold)
        static let largeTitle = Font.system(size: 38, weight: .bold)
        static let title = Font.system(size: 34, weight: .bold)
        static let rowTitle = Font.system(size: 20, weight: .semibold)
        static let heading = Font.system(size: 26, weight: .semibold)
        static let wordmark = Font.system(size: 28, weight: .bold)
        static let body = Font.system(size: 20, weight: .regular)
        static let navItem = Font.system(size: 20, weight: .medium)
        static let button = Font.system(size: 21, weight: .semibold)
        static let caption = Font.system(size: 15, weight: .regular)
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
