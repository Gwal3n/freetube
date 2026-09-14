import Observation
import SwiftUI

/// Coordinates the playback controls' low-frequency presentation state and auto-hide lifetime.
/// Playback itself remains owned by `PlayerStateManager`.
@available(iOS 17.0, *)
@MainActor
@Observable
final class PlayerControlsVisibilityModel {
    private(set) var isVisible = true

    private var hideTask: Task<Void, Never>?

    func toggle(isPlaying: Bool, reduceMotion: Bool) {
        if isVisible {
            hide(reduceMotion: reduceMotion)
        } else {
            show(isPlaying: isPlaying, reduceMotion: reduceMotion)
        }
    }

    func show(isPlaying: Bool, reduceMotion: Bool) {
        cancelAutoHide()
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
            isVisible = true
        }
        guard isPlaying else { return }

        hideTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(3))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.hide(reduceMotion: reduceMotion)
        }
    }

    func hide(reduceMotion: Bool) {
        cancelAutoHide()
        withAnimation(reduceMotion ? nil : .easeIn(duration: 0.18)) {
            isVisible = false
        }
    }

    func cancelAutoHide() {
        hideTask?.cancel()
        hideTask = nil
    }
}
