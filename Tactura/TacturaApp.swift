import SwiftUI

@main
struct TacturaApp: App {
    @State private var appState = AppState()
    @State private var dependencies = AppDependencies()

    /// No-op unless launched with `--depth-bench`.
    init() { DepthBench.runIfRequested() }

    var body: some Scene {
        WindowGroup {
            // No-op on iPad; scales the iPad canvas to fill a phone screen.
            DesignCanvas {
                RootView()
                    .environment(appState)
                    .environment(dependencies)
            }
        }
    }
}
