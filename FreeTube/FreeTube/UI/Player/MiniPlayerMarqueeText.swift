import SwiftUI

/// A vertically stable SwiftUI replacement for LNPopupController's native marquee labels.
/// The native labels can receive an undersized line box on iOS 26, clipping both ascenders and
/// descenders. Keeping measurement and animation inside this leaf also avoids rebuilding the
/// popup item as playback progress changes.
@available(iOS 17.0, *)
struct MiniPlayerMarqueeText: View {
    let text: String
    let font: Font
    let color: Color
    let height: CGFloat

    @State private var textWidth: CGFloat = 0
    @State private var availableWidth: CGFloat = 0
    @State private var offset: CGFloat = 0

    private let gap: CGFloat = 28

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                measuredText.hidden()

                HStack(spacing: gap) {
                    renderedText
                    if textWidth > availableWidth {
                        renderedText
                    }
                }
                .fixedSize(horizontal: true, vertical: false)
                .offset(x: offset)
            }
            .frame(width: proxy.size.width, height: height, alignment: .leading)
            .clipped()
            .onAppear {
                availableWidth = proxy.size.width
                restartAnimation()
            }
            .onChange(of: proxy.size.width) { _, width in
                availableWidth = width
                restartAnimation()
            }
        }
        .frame(height: height)
        .onPreferenceChange(MiniPlayerTextWidthKey.self) { width in
            guard abs(textWidth - width) > 0.5 else { return }
            textWidth = width
            restartAnimation()
        }
        .onChange(of: text) { _, _ in
            offset = 0
        }
        .accessibilityLabel(Text(verbatim: text))
    }

    private var renderedText: some View {
        Text(verbatim: text)
            .font(font)
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    private var measuredText: some View {
        renderedText.background {
            GeometryReader { proxy in
                Color.clear.preference(key: MiniPlayerTextWidthKey.self, value: proxy.size.width)
            }
        }
    }

    private func restartAnimation() {
        offset = 0
        guard textWidth > availableWidth, availableWidth > 0 else { return }
        let distance = textWidth + gap
        let duration = max(6, Double(distance / 28))
        DispatchQueue.main.async {
            withAnimation(.linear(duration: duration).repeatForever(autoreverses: false)) {
                offset = -distance
            }
        }
    }
}

private struct MiniPlayerTextWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
