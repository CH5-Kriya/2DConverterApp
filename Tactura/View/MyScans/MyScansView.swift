import SwiftUI

struct MyScansView: View {
    @State private var model: MyScansViewModel

    /// A standing preference, not a per-visit one — see `ScanLayout`.
    @AppStorage("myScansLayout") private var layout: ScanLayout = .list

    /// Three across, as the design draws it. The minimum stays low enough that
    /// the count survives a narrower window rather than dropping to two.
    private let columns = [GridItem(.adaptive(minimum: 220, maximum: 340), spacing: 24)]

    init(dependencies: AppDependencies) {
        _model = State(initialValue: MyScansViewModel(dependencies: dependencies))
    }

    var body: some View {
        @Bindable var model = model

        ScreenScaffold(title: "My Scans",
                       subtitle: "Find all of your scanned artworks here") {
            VStack(alignment: .leading, spacing: 24) {
                controls
                content
            }
        }
        .task { await model.load() }
    }

    private var controls: some View {
        @Bindable var model = model

        return HStack(alignment: .center, spacing: 18) {
            Text("Search projects")
                .font(Theme.Typography.sectionTitle)
                .foregroundStyle(Theme.Palette.white)
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)

            Spacer(minLength: 16)

            ScanLayoutToggle(layout: $layout)
            ScanSearchField(query: $model.query)
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.hasNoProjects {
            EmptyStateView(
                systemImage: "square.stack.3d.up.slash",
                title: "No scans yet",
                message: "Start a new project from Home to turn a 2D image into a tactile 2.5D model."
            )
        } else if model.hasNoMatches {
            EmptyStateView(
                systemImage: "magnifyingglass",
                title: "No project matches “\(model.query)”",
                message: "Try a shorter word, or clear the search to see everything again."
            )
        } else {
            ScrollView {
                switch layout {
                case .list: list
                case .grid: grid
                }
            }
            .scrollIndicators(.hidden)
            // Cross-fade rather than reflow: the two layouts share no geometry,
            // so animating between them lands as noise instead of continuity.
            .animation(.easeInOut(duration: 0.18), value: layout)
        }
    }

    private var list: some View {
        LazyVStack(spacing: 32) {
            ForEach(model.visible) { project in
                link(project) { ScanListRow(project: project) }
            }
        }
        .padding(.bottom, 24)
    }

    private var grid: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
            ForEach(model.visible) { project in
                link(project) { ScanGridCard(project: project) }
            }
        }
        .padding(.bottom, 24)
    }

    @ViewBuilder
    private func link<Label: View>(_ project: Project,
                                   @ViewBuilder label: () -> Label) -> some View {
        NavigationLink(value: AppDestination.project(project.id)) {
            label()
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Delete", role: .destructive) {
                Task { await model.delete(project) }
            }
        }
    }
}

#if DEBUG
#Preview(traits: .landscapeLeft) {
    NavigationStack {
        MyScansView(dependencies: .preview)
    }
    .background(Theme.Palette.canvas)
    .preferredColorScheme(.dark)
}
#endif
