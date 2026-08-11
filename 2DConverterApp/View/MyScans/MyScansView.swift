import SwiftUI

struct MyScansView: View {
    @State private var model: MyScansViewModel

    private let columns = [GridItem(.adaptive(minimum: 240, maximum: 320), spacing: 24)]

    init(dependencies: AppDependencies) {
        _model = State(initialValue: MyScansViewModel(projects: dependencies.projects))
    }

    var body: some View {
        ScreenScaffold(title: "My Scans",
                       subtitle: "\(model.items.count) project\(model.items.count == 1 ? "" : "s")") {
            if model.isEmpty {
                EmptyStateView(
                    systemImage: "square.stack.3d.up.slash",
                    title: "No scans yet",
                    message: "Start a new project from Home to turn a 2D image into a tactile 2.5D model."
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
                        ForEach(model.items) { project in
                            NavigationLink(value: AppDestination.project(project.id)) {
                                ProjectCard(project: project)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Delete", role: .destructive) {
                                    Task { await model.delete(project) }
                                }
                            }
                        }
                    }
                    .padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)
            }
        }
        .task { await model.load() }
    }
}

#Preview(traits: .landscapeLeft) {
    NavigationStack {
        MyScansView(dependencies: .preview)
    }
    .background(Theme.Palette.canvas)
    .preferredColorScheme(.dark)
}
