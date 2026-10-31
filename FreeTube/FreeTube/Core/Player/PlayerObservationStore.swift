import AVFoundation
import Foundation

/// Owns AVPlayer observation registration and token lifetimes.
/// Playback decisions remain in PlayerStateManager's event handlers.
@available(iOS 17.0, *)
@MainActor
final class PlayerObservationStore {
    private var time: Any?
    private var timeControlStatus: NSKeyValueObservation?
    private var end: NSObjectProtocol?
    var itemStatus: NSKeyValueObservation?
    var itemPresentationSize: NSKeyValueObservation?
    var itemLoadedTimeRanges: NSKeyValueObservation?
    var itemFailedToEnd: NSObjectProtocol?
    var itemErrorLog: NSObjectProtocol?
    var itemAccessLog: NSObjectProtocol?

    func installPlayerObservers(
        on player: AVQueuePlayer,
        onTime: @escaping @MainActor (CMTime) -> Void,
        onEnd: @escaping @MainActor (AVPlayerItem) -> Void,
        onTransportChange: @escaping @MainActor () -> Void
    ) {
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        time = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { value in
            Task { @MainActor in onTime(value) }
        }
        end = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { notification in
            guard let item = notification.object as? AVPlayerItem else { return }
            Task { @MainActor in onEnd(item) }
        }
        timeControlStatus = player.observe(\.timeControlStatus, options: [.new, .initial]) { _, _ in
            Task { @MainActor in onTransportChange() }
        }
    }

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
