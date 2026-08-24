import SwiftUI

struct SidebarRow: View {
    let route: AppRoute
    let isSelected: Bool
    let isExpanded: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SidebarItemLabel(
                systemImage: isSelected ? route.selectedIcon : route.icon,
                title: route.title,
                isExpanded: isExpanded,
                isSelected: isSelected
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(route.title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// Shared between the nav rows and the collapse toggle so both keep the same
/// pill geometry in either sidebar mode.
struct SidebarItemLabel: View {
    let systemImage: String
    let title: String
    let isExpanded: Bool
    let isSelected: Bool

    var body: some View {
        Group {
            if isExpanded {
                HStack(spacing: 18) {
                    icon
                    Text(title)
                        .font(Theme.Typography.navItem)
                        .fixedSize()
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20)
                .frame(height: Theme.Metrics.sidebarRowHeight)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                icon
                    .frame(width: Theme.Metrics.sidebarRailItemSize,
                           height: Theme.Metrics.sidebarRailItemSize)
                    .frame(maxWidth: .infinity)
            }
        }
        // Unselected items step back rather than all reading as current. In the
        // rail there is no label to carry the distinction, so colour is the
        // only thing left to carry it.
        .foregroundStyle(isSelected ? Theme.Palette.white : Theme.Palette.textInactive)
        .background {
            RoundedRectangle(cornerRadius: isExpanded
                             ? Theme.Metrics.sidebarRowRadius
                             : Theme.Metrics.sidebarRailItemRadius,
                             style: .continuous)
                .fill(isSelected ? Theme.Palette.selectedFill : .clear)
                .frame(width: isExpanded ? nil : Theme.Metrics.sidebarRailItemSize,
                       height: isExpanded ? nil : Theme.Metrics.sidebarRailItemSize)
        }
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.18), value: isSelected)
    }

    private var icon: some View {
        Image(systemName: systemImage)
            .font(.system(size: 20, weight: .medium))
            .frame(width: 28)
    }
}

#Preview {
    VStack(spacing: 6) {
        SidebarRow(route: .home, isSelected: true, isExpanded: true) {}
        SidebarRow(route: .myScans, isSelected: false, isExpanded: true) {}
        SidebarRow(route: .home, isSelected: true, isExpanded: false) {}
    }
    .padding()
    .background(Theme.Palette.sidebar)
    .preferredColorScheme(.dark)
}
