import SwiftUI

struct SettingsView: View {
    var body: some View {
        ScreenScaffold(title: "Settings") {
            EmptyStateView(
                systemImage: "gearshape",
                title: "Nothing here yet",
                message: "Settings have not been designed. Wire them up once the screens land."
            )
        }
    }
}

#Preview(traits: .landscapeLeft) {
    SettingsView()
        .background(Theme.Palette.canvas)
        .preferredColorScheme(.dark)
}
