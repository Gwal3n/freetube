import AVFoundation
import Foundation

/// Applies the selected HLS resolution ceilings without replacing the current item.
@available(iOS 17.0, *)
enum PlayerQualityPolicy {
    static func apply(
        to item: AVPlayerItem,
        quality: VideoQuality,
        cellularQuality: VideoQuality
    ) {
        // Reset both ceilings first so returning to Auto also updates an already-playing item.
        item.preferredMaximumResolution = .zero
        item.preferredMaximumResolutionForExpensiveNetworks = .zero
        guard quality != .audioOnly else { return }

        let globalHeightCap = quality == .auto ? nil : quality.heightCap
        if let globalHeightCap, globalHeightCap > 0 {
            item.preferredMaximumResolution = CGSize(
                width: globalHeightCap * 16 / 9, height: globalHeightCap
            )
        }
        if cellularQuality != .auto, let cellularHeightCap = cellularQuality.heightCap,
           cellularHeightCap > 0 {
            let heightCap = min(globalHeightCap ?? cellularHeightCap, cellularHeightCap)
            item.preferredMaximumResolutionForExpensiveNetworks = CGSize(
                width: heightCap * 16 / 9, height: heightCap
            )
        }
    }
}
