import AVFoundation
import Foundation

/// Prepares playback candidates and bounds remote paired-track preparation.
/// AVFoundation may finish a cancelled paired load later; its result is ignored by token.
@MainActor
final class PlayerItemPreparationGate {
    enum Outcome {
        case ready(AVPlayerItem)
        case failed(String)
        case timedOut
        case cancelled
    }

    private var continuation: CheckedContinuation<Outcome, Never>?
    private var preparationTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var token = 0

    func prepare(
        candidate: PlaybackCandidate,
        factory: PlaybackItemFactory,
        videoID: String,
        timeout: Duration
    ) async -> Outcome {
        finish(.cancelled, token: token)
        if Task.isCancelled { return .cancelled }
        // Ordinary candidates do not need the paired-track timeout, but share the same
        // cancellation and error contract as paired candidates at the resolver boundary.
        if candidate.strategy != .nativePaired {
            do {
                return .ready(try await factory.makeItem(for: candidate))
            } catch is CancellationError {
                return .cancelled
            } catch {
                return .failed(PlayerItemReadinessGate.describe(itemError: error))
            }
        }
        token &+= 1
        let currentToken = token
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                timeoutTask = Task { [weak self] in
                    do {
                        try await Task.sleep(for: timeout)
                    } catch {
                        return
                    }
                    self?.finish(.timedOut, token: currentToken)
                }
                preparationTask = Task { [weak self] in
                    do {
                        let item = try await factory.makeItem(for: candidate, videoID: videoID)
                        self?.finish(.ready(item), token: currentToken)
                    } catch is CancellationError {
                        self?.finish(.cancelled, token: currentToken)
                    } catch {
                        self?.finish(
                            .failed(PlayerItemReadinessGate.describe(itemError: error)),
                            token: currentToken
                        )
                    }
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.finish(.cancelled, token: currentToken)
            }
        }
    }

    private func finish(_ outcome: Outcome, token: Int) {
        guard token == self.token, let continuation else { return }
        self.continuation = nil
        preparationTask?.cancel()
        timeoutTask?.cancel()
        preparationTask = nil
        timeoutTask = nil
        continuation.resume(returning: outcome)
    }
}
