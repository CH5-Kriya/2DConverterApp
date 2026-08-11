import SwiftUI

struct HomeView: View {
    @Environment(AppState.self) private var appState
    @State private var model: HomeViewModel

    init(dependencies: AppDependencies) {
        _model = State(initialValue: HomeViewModel(projects: dependencies.projects))
    }

    var body: some View {
        Group {
            if model.isFirstTime {
                FirstRunHome()
            } else if model.hasLoaded {
                ReturningHome(recent: model.recent)
            } else {
                Color.clear
            }
        }
        .task { await model.load() }
    }
}

// MARK: - First run

private struct FirstRunHome: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                copy
                    .frame(width: proxy.size.width * 0.58, alignment: .leading)
                    .padding(.leading, Theme.Metrics.contentPadding)

                HeroArtworkView()
                    .frame(maxWidth: .infinity)
                    .scaleEffect(1.18)
                    .accessibilityHidden(true)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private var copy: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Line breaks are authored, not wrapped; the scale factor keeps
            // them intact on narrower iPads instead of reflowing to four lines.
            Text("Turn 2D Images\ninto 2.5D Models")
                .font(Theme.Typography.display)
                .foregroundStyle(Theme.Palette.textPrimary)
                .lineSpacing(6)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: true)

            Text("Scan any 2D image and bring it to life in 3D\nFast, simple, powerful")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Palette.textSecondary)
                .lineSpacing(4)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .padding(.top, 28)

            VStack(alignment: .leading, spacing: 20) {
                Button {
                    appState.isPresentingNewProject = true
                } label: {
                    Label("New Project", systemImage: "plus")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.kriyaPrimary)

                Button("Tutorials") {
                    appState.select(.tutorials)
                }
                .buttonStyle(.kriyaSecondary)
            }
            .padding(.top, 56)
        }
    }
}

// MARK: - Returning

private struct ReturningHome: View {
    @Environment(AppState.self) private var appState
    let recent: [Project]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Good to see you again!")
                .font(Theme.Typography.largeTitle)
                .foregroundStyle(Theme.Palette.textPrimary)

            Text("Ready to turn your 2D into 3D again?")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Palette.textSecondary)
                .padding(.top, 10)

            HStack(alignment: .top, spacing: 40) {
                StartNewProjectCard {
                    appState.isPresentingNewProject = true
                }
                .frame(maxWidth: .infinity)

                RecentScansPanel(recent: recent)
                    .frame(maxWidth: .infinity)
            }
            .frame(maxHeight: 450)
            .padding(.top, 56)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Metrics.contentPadding)
        .padding(.top, 56)
        .padding(.bottom, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

#Preview("Returning", traits: .landscapeLeft) {
    HomeView(dependencies: .preview)
        .environment(AppState())
        .background(Theme.Palette.canvas)
        .preferredColorScheme(.dark)
}

#Preview("First run", traits: .landscapeLeft) {
    HomeView(dependencies: AppDependencies(projects: InMemoryProjectRepository(seed: [])))
        .environment(AppState())
        .background(Theme.Palette.canvas)
        .preferredColorScheme(.dark)
}
