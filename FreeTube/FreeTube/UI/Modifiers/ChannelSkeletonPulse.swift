import SwiftUI

/// A gentle loading pulse applied only while the channel skeleton is mounted. Unlike a moving
/// shimmer, it has no geometry work per frame and leaves the loaded channel entirely untouched.
@available(iOS 17.0, *)
struct ChannelSkeletonPulse: ViewModifier {
    let reduceMotion: Bool

    @State private var isDimmed = false

    func body(content: Content) -> some View {
        content
            .opacity(isDimmed ? 0.72 : 1)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.25).repeatForever(autoreverses: true)) {
                    isDimmed = true
                }
            }
            .onChange(of: reduceMotion) { _, shouldReduce in
                if shouldReduce {
                    isDimmed = false
                } else {
                    withAnimation(.easeInOut(duration: 1.25).repeatForever(autoreverses: true)) {
                        isDimmed = true
                    }
                }
            }
    }
}
