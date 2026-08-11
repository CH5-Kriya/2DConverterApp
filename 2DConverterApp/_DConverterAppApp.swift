import SwiftUI

@main
struct _DConverterAppApp: App {
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
