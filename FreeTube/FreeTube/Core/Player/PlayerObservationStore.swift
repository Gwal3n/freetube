import AVFoundation
import Foundation

/// Owns AVPlayer observation tokens and removes them when an item is replaced or playback ends.
/// Callback behavior remains in PlayerStateManager; this type only manages observer lifetimes.
@available(iOS 17.0, *)
@MainActor
final class PlayerObservationStore {
    var time: Any?
    var timeControlStatus: NSKeyValueObservation?
    var end: NSObjectProtocol?
    var itemStatus: NSKeyValueObservation?
    var itemPresentationSize: NSKeyValueObservation?
    var itemLoadedTimeRanges: NSKeyValueObservation?
    var itemFailedToEnd: NSObjectProtocol?
    var itemErrorLog: NSObjectProtocol?
    var itemAccessLog: NSObjectProtocol?

    func clearLoadedTimeRanges() {
        itemLoadedTimeRanges?.invalidate()
        itemLoadedTimeRanges = nil
    }

    func clearItem() {
        itemStatus?.invalidate()
        itemStatus = nil
        itemPresentationSize?.invalidate()
        itemPresentationSize = nil
        clearLoadedTimeRanges()
        Self.removeNotification(&itemFailedToEnd)
        Self.removeNotification(&itemErrorLog)
        Self.removeNotification(&itemAccessLog)
    }

    func clearAll(on player: AVQueuePlayer) {
        if let time { player.removeTimeObserver(time) }
        time = nil
        timeControlStatus?.invalidate()
        timeControlStatus = nil
        Self.removeNotification(&end)
        clearItem()
    }

    private static func removeNotification(_ token: inout NSObjectProtocol?) {
        if let token { NotificationCenter.default.removeObserver(token) }
        token = nil
    }
}
