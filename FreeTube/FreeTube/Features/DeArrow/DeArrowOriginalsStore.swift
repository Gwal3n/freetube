import Observation

/// Session-only original/replacement choices shared by every appearance of the same video.
/// These are display preferences, never mutations to saved video metadata.
@available(iOS 17.0, *)
@MainActor
@Observable
final class DeArrowOriginalsStore {
    static let shared = DeArrowOriginalsStore()
    private(set) var videoIDs: Set<String> = []
    private var order: [String] = []

    func toggle(videoID: String) {
        if videoIDs.remove(videoID) != nil {
            order.removeAll { $0 == videoID }
        } else {
            videoIDs.insert(videoID)
            order.append(videoID)
            if order.count > 500 {
                videoIDs.remove(order.removeFirst())
            }
        }
    }
}
