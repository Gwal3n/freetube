import Foundation
import Observation

/// Read-only live chat for one video. Messages and continuation survive sheet dismiss; polling
/// pauses while closed and resumes without a full bootstrap when reopened.
@available(iOS 17.0, *)
@MainActor
@Observable
final class LiveChatViewModel {
    let videoID: String
    private(set) var messages: [LiveChatMessage] = []
    /// Bumps on every accepted append so the sheet can follow even when the capped count is flat.
    private(set) var messageRevision: Int = 0
    /// Starts true so the sheet entrance transition already includes the loading spinner
    /// instead of popping one in after bootstrap begins.
    private(set) var isLoading = true
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
    /// Keep only a recent window so reopen stays light and the list can stay pinned to live.
    private static let messageLimit = 200
    /// Steady on-screen cadence (~6/sec). Do not accelerate when a poll dumps a backlog —
    /// that recreates the hang-then-burst feel.
    private static let revealInterval: Duration = .milliseconds(160)
    /// Pending cap: drop older queued lines so we stay near live instead of binge-playing catch-up.
    private static let maxPendingReveal = 20
    /// First paint: recent tail only, not the entire bootstrap dump.
    private static let initialSeedCount = 30

    init(videoID: String, service: (any LiveChatServicing)? = nil) {
        self.videoID = videoID
        self.service = service ?? LiveChatService()
    }

    func startPolling() {
        guard pollTask == nil, !chatUnavailable, !chatEnded else { return }
        // Synchronous so the first painted sheet frame already owns the spinner.
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
        revealTask?.cancel()
        revealTask = nil
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
            // Seed with the recent tail only — dumping the full bootstrap looks like a burst.
            commit(Array(added.suffix(Self.initialSeedCount)))
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
            await self?.drainPendingReveal()
        }
    }

    private func drainPendingReveal() async {
        defer { revealTask = nil }
        while !Task.isCancelled {
            guard !pendingReveal.isEmpty else { return }
            let next = pendingReveal.removeFirst()
            commit([next])
            try? await Task.sleep(for: Self.revealInterval)
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
