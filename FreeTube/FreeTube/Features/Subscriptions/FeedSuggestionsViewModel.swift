import Foundation
import Observation

/// Keeps randomly chosen suggestions fixed to subscription rows until the feed changes.
/// Suggestions are display-only: they never enter the saved feed or playback queue.
@available(iOS 17.0, *)
@MainActor
@Observable
final class FeedSuggestionsViewModel {
    private(set) var videosByAnchor: [String: Video] = [:]
    private(set) var playbackProgress: [String: Double] = [:]
    private(set) var watchStatuses: [String: WatchHistoryStatus] = [:]

    @ObservationIgnored private var context = ""
    @ObservationIgnored private var processedIDs: Set<String> = []
    @ObservationIgnored private let service: FeedSuggestionService
    @ObservationIgnored private let writer: PersistenceWriter

    init(
        service: FeedSuggestionService? = nil,
        writer: PersistenceWriter? = nil
    ) {
        self.service = service ?? FeedSuggestionService()
        self.writer = writer ?? .shared
    }

    func clear() {
        context = ""
        processedIDs = []
        videosByAnchor = [:]
        playbackProgress = [:]
        watchStatuses = [:]
    }

    func refreshProgress() async {
        let ids = Array(Set(videosByAnchor.values.map(\.id)))
        guard !ids.isEmpty else { return }
        let expectedContext = context
        let summary = await writer.watchHistorySummary(videoIDs: ids)
        guard context == expectedContext else { return }
        playbackProgress = summary.progress
        watchStatuses = summary.statuses
    }

    func update(
        context newContext: String,
        subscriptionVideos: [Video],
        allSubscriptionIDs: Set<String>,
        density: Int,
        enabled: Bool,
        canFetch: Bool,
        watchFilter: FeedWatchFilter,
        durationFilter: FeedDurationFilter,
        minimumMinutes: Int,
        maximumMinutes: Int
    ) async {
        guard enabled, density > 0 else {
            clear()
            return
        }
        if context != newContext {
            clear()
            context = newContext
        }
        videosByAnchor = videosByAnchor.filter { !allSubscriptionIDs.contains($0.value.id) }
        guard canFetch else { return }

        let newVideos = subscriptionVideos.filter { !processedIDs.contains($0.id) }
        guard !newVideos.isEmpty else { return }
        let target = min(newVideos.count, Int(
            (Double(newVideos.count) * Double(density) / Double(100 - density)).rounded(.down)
        ))
        guard target > 0 else {
            processedIDs.formUnion(newVideos.map(\.id))
            return
        }

        // A fresh first page keeps its opening rows purely subscription content. Later
        // batches can use every row; each anchor receives at most one suggestion.
        let anchorPool = processedIDs.isEmpty
            ? Array(newVideos.dropFirst(min(6, newVideos.count)))
            : newVideos
        guard !anchorPool.isEmpty else {
            processedIDs.formUnion(newVideos.map(\.id))
            return
        }
        let seedCount = min(6, max(1, Int(ceil(Double(target) / 15))))
        let seeds = Array(newVideos.shuffled().prefix(seedCount))
        let expectedContext = context
        let candidates = await service.suggestions(for: seeds)
        guard !Task.isCancelled, context == expectedContext else { return }
        processedIDs.formUnion(newVideos.map(\.id))

        let existingIDs = Set(videosByAnchor.values.map(\.id)).union(allSubscriptionIDs)
        var seen = existingIDs
        let eligible = candidates.shuffled().filter { video in
            guard !video.id.isEmpty,
                  seen.insert(video.id).inserted,
                  !VideoBlocklist.shared.blocks(video),
                  durationFilter.includes(video.duration,
                                          minimumMinutes: minimumMinutes,
                                          maximumMinutes: maximumMinutes) else { return false }
            return true
        }
        guard !eligible.isEmpty else { return }
        let candidatesToCheck = watchFilter == .all
            ? Array(eligible.prefix(min(target, anchorPool.count)))
            : eligible
        let summary = await writer.watchHistorySummary(videoIDs: candidatesToCheck.map(\.id))
        guard !Task.isCancelled, context == expectedContext else { return }
        let filtered = candidatesToCheck.filter { watchFilter.includes(summary.statuses[$0.id]) }
        let anchors = Array(anchorPool.shuffled().prefix(min(target, filtered.count)))
        var updatedVideos = videosByAnchor
        for (anchor, video) in zip(anchors, filtered) {
            updatedVideos[anchor.id] = video
        }
        videosByAnchor = updatedVideos
        playbackProgress.merge(summary.progress) { _, new in new }
        watchStatuses.merge(summary.statuses) { _, new in new }
    }
}
