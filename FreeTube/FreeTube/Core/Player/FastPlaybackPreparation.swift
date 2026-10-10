import AVFoundation
import Foundation

/// Prepares an experimental progressive item without replacing or pausing the working HLS item.
/// The silent, paused probe has no view or audio session; it is detached before the real player
/// adopts the item. Readiness, failure, timeout, and cancellation share one completion funnel.
@available(iOS 17.0, *)
@MainActor
final class FastPlaybackPreparation {
    enum Failure: Error {
        case failed(domain: String, code: Int)
        case timedOut
        case unsupportedRate
        case missingTracks
    }

    private let item: AVPlayerItem
    private let probe = AVPlayer()
    private var observation: NSKeyValueObservation?
    private var continuation: CheckedContinuation<Void, Error>?
    private var timeoutTask: Task<Void, Never>?

    init(item: AVPlayerItem) {
        self.item = item
        probe.isMuted = true
        item.audioTimePitchAlgorithm = .spectral
    }

    func prepare(audioOnly: Bool) async throws -> AVPlayerItem {
        try Task.checkCancellation()
        defer {
            observation?.invalidate()
            observation = nil
            timeoutTask?.cancel()
            timeoutTask = nil
            probe.replaceCurrentItem(with: nil)
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                self.continuation = continuation
                guard !Task.isCancelled else {
                    finish(.failure(CancellationError()))
                    return
                }
                observation = item.observe(\.status, options: [.initial, .new]) { [weak self] _, _ in
                    Task { @MainActor in self?.checkReadiness() }
                }
                probe.replaceCurrentItem(with: item)
                timeoutTask = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(12)) } catch { return }
                    self?.finish(.failure(Failure.timedOut))
                }
                checkReadiness()
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.finish(.failure(CancellationError())) }
        }
        try Task.checkCancellation()
        guard item.canPlayFastForward else { throw Failure.unsupportedRate }
        let audio = try await item.asset.loadTracks(withMediaType: .audio)
        guard !audio.isEmpty else { throw Failure.missingTracks }
        if !audioOnly {
            let video = try await item.asset.loadTracks(withMediaType: .video)
            guard !video.isEmpty else { throw Failure.missingTracks }
        }
        try Task.checkCancellation()
        return item
    }

    private func checkReadiness() {
        switch item.status {
        case .readyToPlay:
            finish(.success(()))
        case .failed:
            let error = item.error as NSError?
            finish(.failure(Failure.failed(domain: error?.domain ?? "unknown", code: error?.code ?? 0)))
        case .unknown:
            break
        @unknown default:
            break
        }
    }

    private func finish(_ result: Result<Void, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: result)
    }
}
