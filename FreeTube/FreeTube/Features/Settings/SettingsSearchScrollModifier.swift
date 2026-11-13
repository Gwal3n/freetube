import SwiftUI

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
                        withAnimation(InterfaceMotion.content) {
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
