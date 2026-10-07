import SwiftUI
import UIKit

/// A non-scrolling native text view gives descriptions exact range-selection handles while the
/// surrounding player panel remains the only scroll owner. Link taps retain the existing chapter
/// seek and external URL behavior. Updates avoid resetting the selection during player redraws.
@available(iOS 17.0, *)
struct RichDescriptionText: UIViewRepresentable {
    @Environment(\.appFontPreset) private var preset
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.openURL) private var openURL

    let parts: [VideoDescriptionPart]
    let fallback: String
    let onSeek: (TimeInterval) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.backgroundColor = .clear
        view.isEditable = false
        view.isSelectable = true
        view.isScrollEnabled = false
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.adjustsFontForContentSizeCategory = true
        view.dataDetectorTypes = []
        view.linkTextAttributes = [.foregroundColor: UIColor.systemBlue]
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.required, for: .vertical)
        view.delegate = context.coordinator
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.onSeek = onSeek
        context.coordinator.openURL = openURL

        let font = preset.uiFont(style: .subheadline, size: 15)
        let coordinator = context.coordinator
        if coordinator.lastParts != parts || coordinator.lastFallback != fallback
            || coordinator.lastPreset != preset || coordinator.lastDynamicTypeSize != dynamicTypeSize {
            view.attributedText = attributedDescription(font: font)
            coordinator.lastParts = parts
            coordinator.lastFallback = fallback
            coordinator.lastPreset = preset
            coordinator.lastDynamicTypeSize = dynamicTypeSize
        }
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: UITextView,
        context: Context
    ) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        let measured = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: ceil(measured.height))
    }

    private func attributedDescription(font: UIFont) -> NSAttributedString {
        let result = NSMutableAttributedString(string: "")
        let defaultAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.label
        ]
        guard !parts.isEmpty else {
            return NSAttributedString(string: fallback, attributes: defaultAttributes)
        }
        for part in parts {
            var attributes = defaultAttributes
            if let url = url(for: part.action) {
                attributes[.link] = url
                attributes[.foregroundColor] = UIColor.systemBlue
            }
            result.append(NSAttributedString(string: part.text, attributes: attributes))
        }
        return result
    }

    private func url(for action: VideoDescriptionPart.Action?) -> URL? {
        switch action {
        case .externalURL(let url): return url
        case .seek(let seconds): return URL(string: "freetube-seek://\(seconds)")
        case .video(let id): return URL(string: "https://www.youtube.com/watch?v=\(id)")
        case .channel(let id): return URL(string: "https://www.youtube.com/channel/\(id)")
        case .playlist(let id):
            let playlistID = id.hasPrefix("VL") ? String(id.dropFirst(2)) : id
            return URL(string: "https://www.youtube.com/playlist?list=\(playlistID)")
        case nil: return nil
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var onSeek: (TimeInterval) -> Void = { _ in }
        var openURL: OpenURLAction?
        var lastParts: [VideoDescriptionPart]?
        var lastFallback: String?
        var lastPreset: AppFontPreset?
        var lastDynamicTypeSize: DynamicTypeSize?

        func textView(
            _ textView: UITextView,
            shouldInteractWith url: URL,
            in characterRange: NSRange,
            interaction: UITextItemInteraction
        ) -> Bool {
            if url.scheme == "freetube-seek", let seconds = TimeInterval(url.host ?? "") {
                onSeek(seconds)
            } else {
                openURL?(url)
            }
            return false
        }
    }
}

struct PlayerPanelScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

extension View {
    /// Reports how far the player's lower feed has moved from its resting top edge.
    func reportPlayerPanelScrollOffset() -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: PlayerPanelScrollOffsetKey.self,
                    value: max(0, -proxy.frame(in: .named("playerPanelScroll")).minY)
                )
            }
        }
    }
}
