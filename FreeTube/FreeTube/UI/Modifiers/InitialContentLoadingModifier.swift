import SwiftUI

/// Keeps the native List mounted during its first local read. Only opacity animates; row layout,
/// selection, reordering, and navigation retain their own system transactions.
@available(iOS 17.0, *)
struct InitialContentLoadingModifier: ViewModifier {
    let hasLoaded: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .animation(reduceMotion ? nil : InterfaceMotion.content) { view in
                view.opacity(hasLoaded ? 1 : 0)
            }
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
