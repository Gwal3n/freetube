import Foundation
import MediaPlayer
import UIKit
import OSLog

/// Keeps `MPNowPlayingInfoCenter.default().nowPlayingInfo` in sync with the player. The
/// `PlayerStateManager` calls `update(...)` and `clear()`.
@MainActor
enum NowPlayingCenter {
    private static let log = AppLog(subsystem: "com.leshko.freetube", category: "NowPlaying")
    private static var cachedTitle = ""
    private static var cachedArtist = ""
    private static var cachedDuration: TimeInterval = -.infinity
    private static var cachedArtworkImage: UIImage?
    private static var cachedBaseInfo: [String: Any] = [:]

    static func update(
        title: String,
        artist: String,
        duration: TimeInterval,
        elapsed: TimeInterval,
        rate: Float,
        artwork: UIImage?
    ) {
        let artworkChanged: Bool
        switch (cachedArtworkImage, artwork) {
        case (nil, nil): artworkChanged = false
        case let (cached?, current?): artworkChanged = cached !== current
        default: artworkChanged = true
        }

        if cachedTitle != title
            || cachedArtist != artist
            || cachedDuration != duration
            || artworkChanged {
            cachedTitle = title
            cachedArtist = artist
            cachedDuration = duration
            cachedArtworkImage = artwork
            cachedBaseInfo = [
                MPMediaItemPropertyTitle: title,
                MPMediaItemPropertyArtist: artist,
                MPMediaItemPropertyPlaybackDuration: duration
            ]
            if let artwork {
                cachedBaseInfo[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(
                    boundsSize: artwork.size
                ) { _ in artwork }
            }
        }

        // Periodic playback ticks copy only the small cached dictionary and change transport
        // values. In particular, they no longer allocate a new MPMediaItemArtwork every 0.5s.
        var info = cachedBaseInfo
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed
        info[MPNowPlayingInfoPropertyPlaybackRate] = rate
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    static func clear() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        cachedTitle = ""
        cachedArtist = ""
        cachedDuration = -.infinity
        cachedArtworkImage = nil
        cachedBaseInfo = [:]
        log.info("Now Playing cleared")
    }
}
