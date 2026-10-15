import SwiftUI

/// Gives a searched control a stable scroll target and a brief, non-interactive highlight.
@available(iOS 17.0, *)
struct SettingsSearchRowModifier: ViewModifier {
    let rowID: String
    @Environment(\.settingsSearchTarget) private var searchTarget
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var highlighted = false

    func body(content: Content) -> some View {
        content
            .id(rowID)
            .listRowBackground(
                Color(uiColor: .secondarySystemGroupedBackground)
                    .overlay {
                        Color.primary.opacity(highlighted ? 0.16 : 0)
                    }
                    .allowsHitTesting(false)
            )
            .task(id: searchTarget) {
                guard searchTarget == rowID else {
                    highlighted = false
                    return
                }
                try? await Task.sleep(for: .milliseconds(280))
                guard !Task.isCancelled else { return }
                if reduceMotion {
                    highlighted = true
                } else {
                    withAnimation(.easeIn(duration: 0.18)) { highlighted = true }
                }
                try? await Task.sleep(for: .seconds(1.4))
                guard !Task.isCancelled else { return }
                if reduceMotion {
                    highlighted = false
                } else {
                    withAnimation(.easeOut(duration: 0.5)) { highlighted = false }
                }
            }
    }
}

@available(iOS 17.0, *)
extension View {
    func settingsSearchRow(_ title: LocalizedStringResource) -> some View {
        modifier(SettingsSearchRowModifier(rowID: String(localized: title)))
    }

    func settingsSearchRow(localizedTitle: String) -> some View {
        modifier(SettingsSearchRowModifier(rowID: localizedTitle))
    }
}
