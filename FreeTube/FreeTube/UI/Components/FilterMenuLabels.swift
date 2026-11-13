import SwiftUI

/// Shared checkmark styling for Feed and Search filter category/option rows.
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
}
