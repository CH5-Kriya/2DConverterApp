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
        case .grid: "square.grid.2x2"
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
            ForEach(Array(ScanLayout.allCases.enumerated()), id: \.element) { index, option in
                if index > 0 {
                    Rectangle()
                        .fill(Theme.Palette.white.opacity(0.3))
                        .frame(width: 1)
                }

                Button {
                    layout = option
                } label: {
                    Image(systemName: option.icon)
                        .font(.system(size: 16, weight: .medium))
                        // The selected half inverts rather than tints: at this
                        // size a fill change is the only state cue that survives
                        // being glanced at.
                        .foregroundStyle(layout == option
                                         ? Theme.Palette.controlFill
                                         : Theme.Palette.white)
                        .frame(width: 58, height: 42)
                        .background(layout == option
                                    ? Theme.Palette.white
                                    : Theme.Palette.controlFill)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.label)
                .accessibilityAddTraits(layout == option ? [.isSelected] : [])
            }
        }
        .frame(height: 42)
        .background(Theme.Palette.controlFill)
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Theme.Palette.white, lineWidth: 0.3)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .animation(.easeOut(duration: 0.15), value: layout)
    }
}

/// Search field matching the toggle's height and corner so the two read as one
/// row of controls.
struct ScanSearchField: View {
    @Binding var query: String
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))

            TextField("Search project", text: $query)
                .textFieldStyle(.plain)
                .font(Theme.Typography.meta)
                .focused($focused)
                .submitLabel(.search)

            if !query.isEmpty {
                Button {
                    query = ""
                    focused = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        // One dimming for the whole row, lifted once there is something to
        // read: an empty field is a prompt, a filled one is content.
        .foregroundStyle(Theme.Palette.white.opacity(query.isEmpty && !focused ? 0.44 : 1))
        .padding(.horizontal, 12)
        .frame(width: 190, height: 42)
        .background(Theme.Palette.controlFill)
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Theme.Palette.white, lineWidth: 0.3)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

