import SwiftUI

/// Shared checkmark styling and active-dot badge for Feed, Search, and local-playlist filter menus.
@available(iOS 17.0, *)
enum FilterMenuLabels {
    @ViewBuilder
    static func category(_ title: LocalizedStringKey, active: Bool) -> some View {
        if active {
            Label(title, systemImage: "checkmark")
        } else {
            Text(title)
        }
    }

    @ViewBuilder
    static func option(_ title: String, selected: Bool) -> some View {
        if selected {
            Label(title, systemImage: "checkmark")
        } else {
            Text(title)
        }
    }

    /// Trailing badge on the filter toolbar glyph when any category is narrowed.
    @ViewBuilder
    static func activeDot(isActive: Bool, color: Color = .primary) -> some View {
        if isActive {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
        }
    }
}
