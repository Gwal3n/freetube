import Foundation

/// One row in a YouTube search response, in the order the server returned it.
enum SearchHit: Identifiable, Hashable, Sendable {
    case video(Video)
    case channel(Channel)
    case playlist(Playlist)

    var id: String {
        switch self {
        case .video(let video): "v:\(video.id)"
        case .channel(let channel): "c:\(channel.id)"
        case .playlist(let playlist): "p:\(playlist.id)"
        }
    }
}
