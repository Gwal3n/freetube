import Foundation
import SwiftData

/// A resumable, app-owned metadata pass over one local playlist. The index and video updates are
/// committed together after each lookup, so relaunch resumes at the first unfinished video.
@available(iOS 17.0, *)
@Model
final class LocalPlaylistRefreshJob {
    @Attribute(.unique) var playlistID: String
    var videoIDsJSON: String
    var nextIndex: Int
    var total: Int
    var failures: Int
    var startedAt: Date

    init(playlistID: String, videoIDsJSON: String, total: Int) {
        self.playlistID = playlistID
        self.videoIDsJSON = videoIDsJSON
        self.nextIndex = 0
        self.total = total
        self.failures = 0
        self.startedAt = .now
    }
}
