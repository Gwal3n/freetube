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
    /// Keep only a recent window so reopen stays light and the list can stay pinned to live.
    private static let messageLimit = 200

    init(videoID: String, service: (any LiveChatServicing)? = nil) {
        self.videoID = videoID
        self.service = service ?? LiveChatService()
    }

    func startPolling() {
        guard pollTask == nil, !chatUnavailable, !chatEnded else { return }
        pollTask = Task { [weak self] in
            await self?.runPollingLoop()
        }
        startRevealIfNeeded()
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
        isPolling = false
        // Keep pendingReveal; draining resumes with the next startPolling.
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
                    // Flush anything still queued so the final lines aren't stranded.
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

    /// Deduplicate and either show immediately (cold start) or pace into the list.
    private func enqueue(_ batch: [LiveChatMessage]) {
        guard !batch.isEmpty else { return }
        var added: [LiveChatMessage] = []
        for message in batch where knownIDs.insert(message.id).inserted {
            added.append(message)
        }
        guard !added.isEmpty else { return }

        // First paint should fill the sheet at once; live traffic is revealed steadily.
        if messages.isEmpty {
            commit(added)
            return
        }

        pendingReveal.append(contentsOf: added)
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
            let backlog = pendingReveal.count
            // Faster when a backlog builds so reconnect dumps don't take forever; slower when
            // quiet so poll batches don't land as one visual spike.
            let delayMs: Int
            switch backlog {
            case 40...: delayMs = 35
            case 20..<40: delayMs = 55
            case 8..<20: delayMs = 80
            default: delayMs = 110
            }
            try? await Task.sleep(for: .milliseconds(delayMs))
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
