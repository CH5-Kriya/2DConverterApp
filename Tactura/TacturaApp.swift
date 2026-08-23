import SwiftUI

@main
struct TacturaApp: App {
    @State private var appState = AppState()
    @State private var dependencies = AppDependencies()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .environment(dependencies)
        }
    }
}
