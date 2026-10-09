import AVFoundation
import Observation
import UIKit

/// Owns one vertical video-surface gesture without making the whole player redraw per pan sample.
/// Volume is AVPlayer-relative: iOS has no public setter for the device's system volume.
@available(iOS 17.0, *)
@Observable
@MainActor
final class PlayerSwipeAdjustmentModel {
    enum Kind: Equatable {
        case brightness
        case volume
    }

    private(set) var kind: Kind?
    private(set) var level: CGFloat = 0

    @ObservationIgnored private var isVertical: Bool?
    @ObservationIgnored private var startingLevel: CGFloat = 0
    @ObservationIgnored private var hideTask: Task<Void, Never>?

    func update(
        translation: CGSize,
        startLocation: CGPoint,
        surfaceFrame: CGRect,
        controlsVisible: Bool,
        player: PlayerStateManager
    ) {
        if isVertical == nil {
            let topClearance: CGFloat = controlsVisible ? 64 : 24
            let bottomClearance: CGFloat = controlsVisible ? 84 : 24
            isVertical = abs(translation.height) > abs(translation.width) * 1.15
            guard isVertical == true,
                  surfaceFrame.width > 0,
                  surfaceFrame.height > topClearance + bottomClearance + 32,
                  // Keep top controls and the scrubber's touch area for their own actions.
                  startLocation.y > surfaceFrame.minY + topClearance,
                  startLocation.y < surfaceFrame.maxY - bottomClearance else {
                isVertical = false
                return
            }

            hideTask?.cancel()
            let selectedKind: Kind = startLocation.x < surfaceFrame.midX ? .brightness : .volume
            kind = selectedKind
            startingLevel = selectedKind == .brightness
                ? UIScreen.main.brightness
                : CGFloat(player.player.volume)
            level = startingLevel
        }

        guard isVertical == true, let kind else { return }
        let travel = max(170, min(360, surfaceFrame.height * 0.7))
        let adjustedLevel = min(1, max(0, startingLevel - translation.height / travel))
        guard abs(adjustedLevel - level) >= 0.002 else { return }
        level = adjustedLevel
        switch kind {
        case .brightness:
            UIScreen.main.brightness = adjustedLevel
        case .volume:
            player.setPlaybackVolume(Float(adjustedLevel))
        }
    }

    func finish() {
        isVertical = nil
        guard kind != nil else { return }
        hideTask?.cancel()
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            self?.kind = nil
        }
    }

    func cancel() {
        hideTask?.cancel()
        hideTask = nil
        isVertical = nil
        kind = nil
    }
}
