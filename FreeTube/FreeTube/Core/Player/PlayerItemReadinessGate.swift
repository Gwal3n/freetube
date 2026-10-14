import AVFoundation
import Foundation

/// The single continuation parked while an AVPlayerItem candidate is being validated.
/// PlayerStateManager owns the sole status observer and forwards its result here.
@MainActor
final class PlayerItemReadinessGate {
    enum Outcome {
        case ready
        case failed(String)
        case timedOut
    }

    private var continuation: CheckedContinuation<Outcome, Never>?
    private var item: AVPlayerItem?
    private var token = 0

    /// KVO, timeout, and cancellation all settle through `finish(_:token:)`, which clears the
    /// continuation before resuming it. The status is also read before and after parking, closing
    /// the gap where an item could become ready before the KVO callback reaches the main actor.
    func wait(for item: AVPlayerItem, timeout: Duration) async -> Outcome {
        // Settle a wait that outlived its caller before adopting a new candidate.
        finish(.failed("superseded"), token: token)

        switch item.status {
        case .readyToPlay:
            return .ready
        case .failed:
            return .failed(Self.describe(itemError: item.error))
        case .unknown:
            break
        @unknown default:
            break
        }

        if Task.isCancelled { return .failed("cancelled") }

        token += 1
        let currentToken = token
        self.item = item

        let timeoutTask = Task { [weak self] in
            do {
                try await Task.sleep(for: timeout)
            } catch {
                return
            }
            self?.finish(.timedOut, token: currentToken)
        }
        defer { timeoutTask.cancel() }

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                switch item.status {
                case .readyToPlay:
                    self.finish(.ready, for: item)
                case .failed:
                    self.finish(.failed(Self.describe(itemError: item.error)), for: item)
                case .unknown:
                    break
                @unknown default:
                    break
                }
            }
        } onCancel: {
            // The cancellation handler is nonisolated. Only the token crosses actors.
            Task { @MainActor [weak self] in
                self?.finish(.failed("cancelled"), token: currentToken)
            }
        }
    }

    func finish(_ outcome: Outcome, for item: AVPlayerItem) {
        guard self.item === item else { return }
        finish(outcome, token: token)
    }

    private func finish(_ outcome: Outcome, token: Int) {
        guard token == self.token, let continuation else { return }
        self.continuation = nil
        item = nil
        continuation.resume(returning: outcome)
    }

    /// Error userInfo may include a signed playback URL; expose only its domain and code.
    nonisolated static func describe(itemError: Error?) -> String {
        let error = itemError as NSError?
        return "domain=\(error?.domain ?? "?") code=\(error?.code ?? 0)"
    }
}
