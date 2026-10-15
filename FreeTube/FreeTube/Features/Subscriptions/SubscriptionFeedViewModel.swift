import Foundation
import Observation

@available(iOS 17.0, *)
@Observable
@MainActor
final class SubscriptionFeedViewModel {
    private(set) var videos: [Video] = []
    private(set) var playbackProgress: [String: Double] = [:]
    private(set) var watchStatuses: [String: WatchHistoryStatus] = [:]
    private(set) var isRefreshing = false
    private(set) var isLoadingMore = false
    private(set) var refreshedChannels = 0
    private(set) var refreshChannelCount = 0
    private(set) var hasLoaded = false
    /// Changes after a fresh first page is committed, but not while paginating that page.
    private(set) var firstPageRevision = 0
    private(set) var failedChannels: [LocalSubscription] = []
    private(set) var isRefreshWarningDismissed = false
    private(set) var canLoadMore = false
    private(set) var lastRefreshAt: Date?
    private(set) var lastRefreshAttemptAt: Date?
    /// Only a run that reached every subscribed channel advances the automatic refresh schedule.
    private(set) var lastCompleteRefreshAt: Date?
    private(set) var selectedGroupID: UUID?

    private let pageSize = 100
    private var visibleLimit = 100
    private var cacheGeneration = 0
    private var cachedSnapshots: [SubscriptionFeedSnapshot] = []
    @ObservationIgnored private var activeRefreshTask: Task<SubscriptionFeedRefresh, Never>?
    @ObservationIgnored private var activeRefreshID: UUID?

    private let service: any SubscriptionFeedServicing
    private let writer: PersistenceWriter
    private let subscriptions: LocalSubscriptionStore
    private let groups: LocalSubscriptionGroupStore
    private let defaults: UserDefaults
    private let log = AppLog(subsystem: "com.leshko.freetube", category: "SubscriptionFeed")
    private static let lastCompleteRefreshKey = "com.leshko.freetube.lastCompleteSubscriptionFeedRefresh"
    private static let lastCompleteSubscriptionKey = "com.leshko.freetube.lastCompleteSubscriptionIDs"
    private var completedSubscriptionIDs: String?

    init(
        service: any SubscriptionFeedServicing = SubscriptionFeedService(),
        writer: PersistenceWriter = .shared,
        subscriptions: LocalSubscriptionStore = .shared,
        groups: LocalSubscriptionGroupStore = .shared,
        defaults: UserDefaults = .standard
    ) {
        self.service = service
        self.writer = writer
        self.subscriptions = subscriptions
        self.groups = groups
        self.defaults = defaults
        self.completedSubscriptionIDs = defaults.string(forKey: Self.lastCompleteSubscriptionKey)
        let storedCompletion = defaults.double(forKey: Self.lastCompleteRefreshKey)
        self.lastCompleteRefreshAt = storedCompletion > 0
            ? Date(timeIntervalSince1970: storedCompletion) : nil
    }

    var hasSubscriptions: Bool { !subscriptions.subscriptions.isEmpty }
    var lastCompleteRefreshForCurrentSubscriptions: Date? {
        completedSubscriptionIDs == subscriptionIDs ? lastCompleteRefreshAt : nil
    }
    var failedChannelCount: Int { failedChannels.count }

    private var subscriptionIDs: String {
        subscriptions.subscriptions.map(\.id).sorted().joined(separator: ",")
    }
    var selectedGroupName: String? {
        guard let selectedGroupID else { return nil }
        return groups.groups.first(where: { $0.id == selectedGroupID })?.name
    }

    func selectGroup(_ id: UUID?) async {
        selectedGroupID = id
        visibleLimit = pageSize
        await loadCache()
    }

    func groupsChanged() async {
        if let selectedGroupID, !groups.groups.contains(where: { $0.id == selectedGroupID }) {
            self.selectedGroupID = nil
        }
        await loadCache()
    }

    var didLastRefreshCompletelyFail: Bool {
        hasLoaded
            && !isRefreshing
            && refreshChannelCount > 0
            && failedChannelCount >= refreshChannelCount
    }

    func load() async {
        await loadCache()
        hasLoaded = true
        if !Task.isCancelled, videos.isEmpty, hasSubscriptions { await refresh() }
    }

    /// History changes affect progress only; preserve the feed rows and pagination.
    func refreshProgress() async {
        let generation = cacheGeneration
        let summary = await writer.watchHistorySummary(videoIDs: videos.map(\.id))
        guard generation == cacheGeneration else { return }
        playbackProgress = summary.progress
        watchStatuses = summary.statuses
    }

    func refresh() async {
        guard !isRefreshing else { return }
        let priorVisibleIDs = Set(videos.map(\.id))
        let refreshID = UUID()
        activeRefreshID = refreshID
        isRefreshing = true
        lastRefreshAttemptAt = .now
        failedChannels = []
        isRefreshWarningDismissed = false
        refreshedChannels = 0
        let snapshot = subscriptions.subscriptions
        refreshChannelCount = snapshot.count
        let task = Task { [service] in
            await service.refresh(subscriptions: snapshot) { [weak self] completed, total in
                await self?.updateRefreshProgress(completed: completed, total: total, for: refreshID)
            }
        }
        activeRefreshTask = task
        // Once started, a refresh owns its work. Leaving Feed cancels its timer, not the
        // in-flight channel batch; only the explicit Cancel action stops that batch.
        let result = await task.value
        guard activeRefreshID == refreshID else {
            // A cancelled run may already have saved completed channels. Show those cached rows
            // once its in-flight batch has drained, unless a newer refresh has started.
            if activeRefreshID == nil { await loadCache() }
            return
        }
        activeRefreshTask = nil
        activeRefreshID = nil
        if task.isCancelled {
            log.info("Feed refresh cancelled after \(refreshedChannels, privacy: .public)/\(snapshot.count, privacy: .public) channels")
            isRefreshing = false
            refreshedChannels = 0
            refreshChannelCount = 0
            await loadCache()
            return
        }
        failedChannels = result.failedChannels
        if result.succeeded == snapshot.count, result.failedChannels.isEmpty {
            let completedAt = Date.now
            lastCompleteRefreshAt = completedAt
            completedSubscriptionIDs = subscriptionIDs
            defaults.set(completedAt.timeIntervalSince1970, forKey: Self.lastCompleteRefreshKey)
            defaults.set(completedSubscriptionIDs, forKey: Self.lastCompleteSubscriptionKey)
        }
        visibleLimit = pageSize
        await loadCache()
        isRefreshing = false
        let newVisibleCount = Set(videos.map(\.id)).subtracting(priorVisibleIDs).count
        log.info("Feed refresh completed: channels=\(result.succeeded, privacy: .public)/\(snapshot.count, privacy: .public), failed=\(result.failedChannels.count, privacy: .public), visible=\(videos.count, privacy: .public), newly visible IDs=\(newVisibleCount, privacy: .public)")
    }

    func cancelRefresh() {
        guard isRefreshing else { return }
        activeRefreshID = nil
        activeRefreshTask?.cancel()
        activeRefreshTask = nil
        isRefreshing = false
        refreshedChannels = 0
        refreshChannelCount = 0
        failedChannels = []
    }

    func dismissRefreshWarning() {
        isRefreshWarningDismissed = true
    }

    private func updateRefreshProgress(completed: Int, total: Int, for refreshID: UUID) {
        guard activeRefreshID == refreshID else { return }
        refreshedChannels = completed
        refreshChannelCount = total
    }

    func loadMore() async {
        guard canLoadMore, !isLoadingMore, !isRefreshing else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        visibleLimit += pageSize
        await loadCache()
    }

    /// Settings may change while Feed stays mounted behind the Settings sheet. Reorder the
    /// already-loaded snapshots immediately; do not refetch or disturb watch progress.
    func refreshOrdering() {
        guard !cachedSnapshots.isEmpty else { return }
        videos = orderedVideos(from: cachedSnapshots)
    }

    private func orderedVideos(from snapshots: [SubscriptionFeedSnapshot]) -> [Video] {
        let preferences = UserPreferences()
        let configuration = SubscriptionFeedOrdering.Configuration(
            isEnabled: preferences.spaceSubscriptionFeedVideos,
            channelGap: preferences.feedChannelSpacing,
            groupGap: preferences.feedGroupSpacing,
            maximumDateShift: TimeInterval(preferences.feedSpacingMaximumShiftHours) * 60 * 60,
            groups: groups.groups,
            selectedGroupID: selectedGroupID
        )
        return SubscriptionFeedOrdering.diversified(
            snapshots, pageSize: pageSize, configuration: configuration
        ).map(\.video)
    }

    private func loadCache() async {
        cacheGeneration += 1
        let generation = cacheGeneration
        let isFirstPage = visibleLimit == pageSize
        let channelIDs = selectedGroupID.flatMap { id in
            groups.groups.first(where: { $0.id == id })?.channelIDs
        }
        let snapshots = await writer.fetchSubscriptionFeed(limit: visibleLimit, channelIDs: channelIDs)
        let refreshedVideos = orderedVideos(from: snapshots)
        let totalCount = await writer.subscriptionFeedCount(channelIDs: channelIDs)
        let watchSummary = await writer.watchHistorySummary(videoIDs: refreshedVideos.map(\.id))
        let refreshDate = await writer.latestSubscriptionFeedRefreshDate()
        guard generation == cacheGeneration else { return }
        // Commit rows and their progress together, rather than painting fresh rows with stale
        // progress while the remaining persistence reads are suspended.
        cachedSnapshots = snapshots
        videos = refreshedVideos
        canLoadMore = refreshedVideos.count < totalCount
        playbackProgress = watchSummary.progress
        watchStatuses = watchSummary.statuses
        lastRefreshAt = refreshDate
        if isFirstPage { firstPageRevision &+= 1 }
    }
}
