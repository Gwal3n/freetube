import Foundation
import Observation

/// Read-only live chat for one video. Polls only while `startPolling` is active; tokens stay in memory.
@available(iOS 17.0, *)
@MainActor
@Observable
final class LiveChatViewModel {
    private(set) var messages: [LiveChatMessage] = []
    private(set) var isLoading = false
    private(set) var isPolling = false
    private(set) var chatUnavailable = false
    private(set) var chatEnded = false
    var errorState: ErrorState?

    private let videoID: String
    private let service: any LiveChatServicing
    private let log = AppLog(subsystem: "com.leshko.freetube", category: "LiveChat")
    private var pollTask: Task<Void, Never>?
    private var knownIDs = Set<String>()
    private static let messageLimit = 400

    init(videoID: String, service: (any LiveChatServicing)? = nil) {
        self.videoID = videoID
        self.service = service ?? LiveChatService()
    }

    func startPolling() {
        guard pollTask == nil, !chatUnavailable else { return }
        pollTask = Task { [weak self] in
            await self?.runPollingLoop()
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
        isPolling = false
    }

    private func runPollingLoop() async {
        isLoading = messages.isEmpty
        isPolling = true
        defer {
            isLoading = false
            isPolling = false
        }
        do {
            let bootstrap = try await service.bootstrap(videoID: videoID)
            guard !Task.isCancelled else { return }
            var continuation = bootstrap.continuation
            // First page often includes recent history; show it, then keep polling.
            while !Task.isCancelled {
                let page = try await service.poll(
                    continuation: continuation,
                    apiKey: bootstrap.apiKey,
                    clientVersion: bootstrap.clientVersion
                )
                guard !Task.isCancelled else { return }
                isLoading = false
                append(page.messages)
                if page.chatEnded || page.continuation == nil {
                    chatEnded = true
                    log.info("Live chat ended for \(self.videoID, privacy: .public)")
                    return
                }
                continuation = page.continuation ?? continuation
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

    private func append(_ batch: [LiveChatMessage]) {
        guard !batch.isEmpty else { return }
        var added: [LiveChatMessage] = []
        for message in batch where knownIDs.insert(message.id).inserted {
            added.append(message)
        }
        guard !added.isEmpty else { return }
        messages.append(contentsOf: added)
        if messages.count > Self.messageLimit {
            let overflow = messages.count - Self.messageLimit
            let removed = messages.prefix(overflow)
            for message in removed { knownIDs.remove(message.id) }
            messages.removeFirst(overflow)
        }
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
