import LNPopupUI
import SwiftUI

/// Emits only the high-frequency popup progress preference. Keeping this in a leaf view prevents
/// playback ticks from invalidating the sibling title, subtitle, artwork, and bar-button metadata.
@available(iOS 17.0, *)
struct PopupProgressObserver: View {
    @Environment(PlayerStateManager.self) private var player

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .popupProgress(PopupContentWrapper.progress(for: player))
            .accessibilityHidden(true)
    }
}
