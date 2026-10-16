import SwiftUI
import CoreGraphics

/// The compact player's visual frame in window coordinates. Passing the same geometry into the
/// selected tab keeps its passive video layer aligned with the root-owned player during drags.
@available(iOS 17.0, *)
struct FloatingPlayerUnderlayLayout: EnvironmentKey {
    let frameInGlobal: CGRect
    let tabBarTopInGlobal: CGFloat
    let cornerRadius: CGFloat
    let opacity: Double
    let isVisible: Bool

    static let hidden = FloatingPlayerUnderlayLayout(
        frameInGlobal: .zero, tabBarTopInGlobal: 0,
        cornerRadius: 0, opacity: 0, isVisible: false
    )
    static let defaultValue = hidden
}

@available(iOS 17.0, *)
extension EnvironmentValues {
    var floatingPlayerUnderlayLayout: FloatingPlayerUnderlayLayout {
        get { self[FloatingPlayerUnderlayLayout.self] }
        set { self[FloatingPlayerUnderlayLayout.self] = newValue }
    }
}
