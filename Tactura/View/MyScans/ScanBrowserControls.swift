import SwiftUI

/// How the scan browser lays its projects out.
///
/// Backed by `@AppStorage` at the call site rather than `@State`: which of the
/// two a person prefers is a standing preference, not a per-visit one, and
/// having it reset on every launch is the kind of small rudeness that makes a
/// tool feel careless.
enum ScanLayout: String, CaseIterable, Identifiable {
    case grid
    case list

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .grid: "square.grid.2x2.fill"
        case .list: "list.bullet"
        }
    }

    var label: String {
        switch self {
        case .grid: "Grid"
        case .list: "List"
        }
    }
}

/// The paired grid/list control, drawn as one outlined pill split down the
/// middle rather than as two separate buttons — the shared border is what makes
/// it read as a single choice with two states.
struct ScanLayoutToggle: View {
    @Binding var layout: ScanLayout

    var body: some View {
        HStack(spacing: 0) {
            ForEach(ScanLayout.allCases) { option in
                Button {
                    layout = option
                } label: {
                    Image(systemName: option.icon)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(layout == option
                                         ? Theme.Palette.textPrimary
                                         : Theme.Palette.textSecondary)
                        .frame(width: 56, height: 44)
                        .background {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(layout == option
                                      ? Theme.Palette.surfaceSelected
                                      : .clear)
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.label)
                .accessibilityAddTraits(layout == option ? [.isSelected] : [])
            }
        }
        .padding(3)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.Palette.separator, lineWidth: 1)
        }
        .animation(.easeOut(duration: 0.15), value: layout)
    }
}

/// Search field matching the toggle's height and corner so the two read as one
/// row of controls.
struct ScanSearchField: View {
    @Binding var query: String
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.Palette.textSecondary)

            TextField("Search project", text: $query)
                .textFieldStyle(.plain)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.textPrimary)
                .focused($focused)
                .submitLabel(.search)

            if !query.isEmpty {
                Button {
                    query = ""
                    focused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.Palette.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 16)
        // Flexible rather than fixed: in portrait the sidebar leaves too little
        // room for the full width, and shrinking the field is a better trade
        // than squeezing the page title.
        .frame(minWidth: 150, idealWidth: 240, maxWidth: 240)
        .frame(height: 50)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(focused ? Theme.Palette.border : Theme.Palette.separator,
                              lineWidth: 1)
        }
        .animation(.easeOut(duration: 0.15), value: focused)
    }
}

#Preview {
    @Previewable @State var layout: ScanLayout = .list
    @Previewable @State var query = ""

    HStack(spacing: 20) {
        ScanLayoutToggle(layout: $layout)
        ScanSearchField(query: $query)
    }
    .padding(40)
    .background(Theme.Palette.canvas)
    .preferredColorScheme(.dark)
}
