import SwiftUI

/// Keeps the native List mounted during its first local read without a placeholder-content
/// animation wrapper around its navigation environment.
@available(iOS 17.0, *)
struct InitialContentLoadingModifier: ViewModifier {
    let hasLoaded: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(hasLoaded ? 1 : 0)
            .animation(reduceMotion ? nil : InterfaceMotion.content, value: hasLoaded)
            .allowsHitTesting(hasLoaded)
            .accessibilityHidden(!hasLoaded)
            .overlay {
                if !hasLoaded {
                    LoadingView()
                        .accessibilityLabel("Loading")
                        .allowsHitTesting(false)
                }
            }
    }
}

extension View {
    @available(iOS 17.0, *)
    func initialContentLoading(hasLoaded: Bool) -> some View {
        modifier(InitialContentLoadingModifier(hasLoaded: hasLoaded))
    }
}
