import SwiftUI
import Kingfisher
import UIKit

extension KFImage {
    /// Downsampled, cached Kingfisher load for list thumbnails. `size` is in points (×3 for retina).
    func thumbnail<Placeholder: View>(
        size: CGSize,
        scale: CGFloat = 3,
        fadeDuration: TimeInterval = 0.15,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) -> KFImage {
        let effectiveFadeDuration = UIAccessibility.isReduceMotionEnabled ? 0 : fadeDuration
        return self
            .placeholder(placeholder)
            .setProcessor(DownsamplingImageProcessor(size: CGSize(
                width: size.width * scale,
                height: size.height * scale
            )))
            .cacheOriginalImage()
            .fade(duration: effectiveFadeDuration)
            .cancelOnDisappear(true)
    }
}
