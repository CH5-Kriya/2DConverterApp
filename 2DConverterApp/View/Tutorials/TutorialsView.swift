import SwiftUI

struct TutorialsView: View {
    var body: some View {
        ScreenScaffold(title: "Tutorials",
                       subtitle: "How to get a relief that reads well by hand") {
            EmptyStateView(
                systemImage: "lightbulb",
                title: "Nothing here yet",
                message: "Tutorial content has not been designed. Wire it up once the screens land."
            )
        }
    }
}

#Preview(traits: .landscapeLeft) {
    TutorialsView()
        .background(Theme.Palette.canvas)
        .preferredColorScheme(.dark)
}
