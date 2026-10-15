import SwiftUI

/// Scrolls a settings Form to the row selected from Settings search after its push mounts.
@available(iOS 17.0, *)
struct SettingsSearchScrollModifier: ViewModifier {
    @Environment(\.settingsSearchTarget) private var searchTarget
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        ScrollViewReader { proxy in
            content
                .task(id: searchTarget) {
                    guard let searchTarget else { return }
                    try? await Task.sleep(for: .milliseconds(220))
                    guard !Task.isCancelled else { return }
                    if reduceMotion {
                        proxy.scrollTo(searchTarget, anchor: .center)
                    } else {
                        withAnimation(.easeInOut(duration: 0.28)) {
                            proxy.scrollTo(searchTarget, anchor: .center)
                        }
                    }
                }
        }
    }
}

@available(iOS 17.0, *)
extension View {
    func scrollToSearchedSetting() -> some View {
        modifier(SettingsSearchScrollModifier())
    }
}
