import SwiftUI

/// Renders YouTube's structured description runs as one flowing SwiftUI Text. External links use
/// the system URL handler; chapter timestamps seek in-place without covering or replacing playback.
@available(iOS 17.0, *)
struct RichDescriptionText: View {
    let parts: [VideoDescriptionPart]
    let fallback: String
    let onSeek: (TimeInterval) -> Void

    var body: some View {
        Text(attributedDescription)
            .tint(.blue)
            .environment(\.openURL, OpenURLAction { url in
                guard url.scheme == "freetube-seek",
                      let seconds = TimeInterval(url.host ?? "") else { return .systemAction }
                onSeek(seconds)
                return .handled
            })
    }

    private var attributedDescription: AttributedString {
        guard !parts.isEmpty else { return AttributedString(fallback) }
        return parts.reduce(into: AttributedString()) { result, part in
            var run = AttributedString(part.text)
            if let url = url(for: part.action) {
                run.link = url
                run.foregroundColor = .blue
            }
            result.append(run)
        }
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
