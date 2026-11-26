import Foundation
import Observation

/// Read-only live chat for one video. Messages and continuation survive sheet dismiss; polling
/// pauses while closed and resumes without a full bootstrap when reopened.
///
/// Poll batches are revealed one message at a time using the same delay curve YouTube.js /
/// FreeTube desktop use (`SmoothedQueue`), so the list looks continuous instead of hang-then-burst.
@available(iOS 17.0, *)
@MainActor
@Observable
final class LiveChatViewModel {
    let videoID: String
    private(set) var messages: [LiveChatMessage] = []
    /// Bumps on every accepted append so followers can react even when the capped count is flat.
    private(set) var messageRevision: Int = 0
    private(set) var isLoading = false
    private(set) var isPolling = false
    private(set) var chatUnavailable = false
    private(set) var chatEnded = false
    var errorState: ErrorState?

    private let service: any LiveChatServicing
    private let log = AppLog(subsystem: "com.leshko.freetube", category: "LiveChat")
    private var pollTask: Task<Void, Never>?
    private var revealTask: Task<Void, Never>?
    private var pendingReveal: [LiveChatMessage] = []
    private var knownIDs = Set<String>()
    private var continuation: String?
    private var apiKey: String?
    private var clientVersion: String?
    private static let messageLimit = 400
    /// Drop older queued lines when catch-up gets ahead of live.
    private static let maxPendingReveal = 40
    /// First paint: show a recent tail immediately, then drip anything newer.
    private static let initialSeedCount = 30
    /// Same base constant YouTube.js uses for smoothed emit spacing.
    private static let smoothBase: Double = 10_000

    init(videoID: String, service: (any LiveChatServicing)? = nil) {
        self.videoID = videoID
        self.service = service ?? LiveChatService()
    }

    func startPolling() {
        guard pollTask == nil, !chatUnavailable, !chatEnded else { return }
        if messages.isEmpty {
            isLoading = true
        }
        pollTask = Task { [weak self] in
            await self?.runPollingLoop()
        }
        startRevealIfNeeded()
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
        isPolling = false
        // Finish any in-flight drip so reopen does not replay a stale backlog.
        revealTask?.cancel()
        revealTask = nil
        flushPendingReveal()
    }

    private func runPollingLoop() async {
        isLoading = messages.isEmpty
        isPolling = true
        defer {
            isLoading = false
            isPolling = false
        }
        do {
            if continuation == nil || apiKey == nil || clientVersion == nil {
                let bootstrap = try await service.bootstrap(videoID: videoID)
                guard !Task.isCancelled else { return }
                continuation = bootstrap.continuation
                apiKey = bootstrap.apiKey
                clientVersion = bootstrap.clientVersion
            }
            guard var activeContinuation = continuation,
                  let apiKey,
                  let clientVersion else { return }

            while !Task.isCancelled {
                let page = try await service.poll(
                    continuation: activeContinuation,
                    apiKey: apiKey,
                    clientVersion: clientVersion
                )
                guard !Task.isCancelled else { return }
                isLoading = false
                enqueue(page.messages)
                if page.chatEnded || page.continuation == nil {
                    chatEnded = true
                    flushPendingReveal()
                    log.info("Live chat ended for \(self.videoID, privacy: .public)")
                    return
                }
                activeContinuation = page.continuation ?? activeContinuation
                continuation = activeContinuation
                try? await Task.sleep(for: page.timeout)
            }
        } catch is CancellationError {
            return
        } catch let error as YouTubeServiceError {
            handle(error)
        } catch {
            handle(.network(error))
        }
    }

    /// Deduplicate and pace into the visible list.
    private func enqueue(_ batch: [LiveChatMessage]) {
        guard !batch.isEmpty else { return }
        var added: [LiveChatMessage] = []
        for message in batch where knownIDs.insert(message.id).inserted {
            added.append(message)
        }
        guard !added.isEmpty else { return }

        if messages.isEmpty {
            // Cold open: paint a recent window immediately so the sheet is not empty while the
            // smoothed drip catches up with the rest of the poll.
            if added.count > Self.initialSeedCount {
                let seed = Array(added.suffix(Self.initialSeedCount))
                let older = Array(added.dropLast(Self.initialSeedCount))
                commit(seed)
                // Older history is skipped — stay near live rather than binge-playing catch-up.
                _ = older
            } else {
                commit(added)
            }
            return
        }

        pendingReveal.append(contentsOf: added)
        if pendingReveal.count > Self.maxPendingReveal {
            pendingReveal.removeFirst(pendingReveal.count - Self.maxPendingReveal)
        }
        startRevealIfNeeded()
    }

    private func startRevealIfNeeded() {
        guard revealTask == nil, !pendingReveal.isEmpty else { return }
        revealTask = Task { [weak self] in
            await self?.runRevealLoop()
        }
    }

    private func runRevealLoop() async {
        defer { revealTask = nil }
        while !Task.isCancelled {
            guard !pendingReveal.isEmpty else { return }
            let delayMs = Self.smoothedDelayMilliseconds(queueLength: pendingReveal.count)
            try? await Task.sleep(for: .milliseconds(delayMs))
            guard !Task.isCancelled, !pendingReveal.isEmpty else { return }
            let next = pendingReveal.removeFirst()
            commit([next])
        }
    }

    private func flushPendingReveal() {
        revealTask?.cancel()
        revealTask = nil
        guard !pendingReveal.isEmpty else { return }
        let leftover = pendingReveal
        pendingReveal.removeAll(keepingCapacity: true)
        commit(leftover)
    }

    private func commit(_ batch: [LiveChatMessage]) {
        guard !batch.isEmpty else { return }
        messages.append(contentsOf: batch)
        if messages.count > Self.messageLimit {
            let overflow = messages.count - Self.messageLimit
            let removed = messages.prefix(overflow)
            for message in removed { knownIDs.remove(message.id) }
            messages.removeFirst(overflow)
        }
        messageRevision &+= 1
    }

    /// Port of YouTube.js `LiveChat.#emitSmoothedActions` delay selection.
    private static func smoothedDelayMilliseconds(queueLength: Int) -> Int {
        let length = max(1, queueLength)
        let base = Self.smoothBase
        if Double(length) < base / 80 {
            var delay = base / Double(length)
            delay *= Double.random(in: 0.5...1.5)
            delay = min(1_000, delay)
            delay = max(80, delay)
            return Int(delay.rounded())
        }
        return 80
    }

    private func handle(_ error: YouTubeServiceError) {
        isLoading = false
        switch error {
        case .videoUnavailable:
            chatUnavailable = true
            log.notice("Live chat unavailable for \(self.videoID, privacy: .public)")
        case .rateLimited:
            errorState = ErrorState(message: String(localized: "Live chat is rate limited. Try again shortly."))
        default:
            errorState = ErrorState(message: String(localized: "Live chat couldn’t be loaded. Please try again."))
            log.notice("Live chat failed: \(error, privacy: .public)")
        }
    }
}
