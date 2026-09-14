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

    func toggle(isPlaying: Bool) {
        if isVisible {
            hide()
        } else {
            show(isPlaying: isPlaying)
        }
    }

    func show(isPlaying: Bool) {
        cancelAutoHide()
        withAnimation(.easeOut(duration: 0.18)) {
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
            self?.hide()
        }
    }

    func hide() {
        cancelAutoHide()
        withAnimation(.easeIn(duration: 0.18)) {
            isVisible = false
        }
    }

    func cancelAutoHide() {
        hideTask?.cancel()
        hideTask = nil
    }
}
