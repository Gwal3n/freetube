import Foundation

@available(iOS 17.0, *)
enum FeedWatchFilter: String, CaseIterable, Identifiable {
    case all, hideWatched, hidePartial, onlyPartial, onlyFinished

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All videos"
        case .hideWatched: "Hide watched"
        case .hidePartial: "Hide partially watched"
        case .onlyPartial: "Only partially watched"
        case .onlyFinished: "Only finished"
        }
    }

    func includes(_ status: WatchHistoryStatus?) -> Bool {
        switch self {
        case .all: true
        case .hideWatched: status == nil
        case .hidePartial: status != .partial
        case .onlyPartial: status == .partial
        case .onlyFinished: status == .finished
        }
    }
}
