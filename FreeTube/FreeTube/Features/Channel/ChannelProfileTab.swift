import Foundation

enum ChannelProfileTab: String, Identifiable, CaseIterable {
    case videos
    case shorts
    case live
    case playlists
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .videos: "Videos"
        case .shorts: "Shorts"
        case .live: "Live"
        case .playlists: "Playlists"
        case .about: "About"
        }
    }
}
