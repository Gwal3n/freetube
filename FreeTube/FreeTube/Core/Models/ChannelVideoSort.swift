import Foundation

enum ChannelVideoSort: String, CaseIterable, Identifiable, Sendable {
    case newest
    case popular
    case oldest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newest: "Newest"
        case .popular: "Popular"
        case .oldest: "Oldest"
        }
    }

    /// YouTube's stable Videos-tab sort parameters. The final protobuf value selects newest (0),
    /// popular (1), or oldest (2); each request returns its own continuation chain.
    var requestParameters: String {
        switch self {
        case .newest: "EgZ2aWRlb3PyBgQKAjoA"
        case .popular: "EgZ2aWRlb3PyBgQKAjoB"
        case .oldest: "EgZ2aWRlb3PyBgQKAjoC"
        }
    }

    func localFallback(_ videos: [Video]) -> [Video] {
        switch self {
        case .newest:
            return videos
        case .popular:
            return videos.sorted { ($0.viewCount ?? 0) > ($1.viewCount ?? 0) }
        case .oldest:
            return Array(videos.reversed())
        }
    }
}
