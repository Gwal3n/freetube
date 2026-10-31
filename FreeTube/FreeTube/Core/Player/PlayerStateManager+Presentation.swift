import CoreGraphics
import Foundation

/// Presentation requests and launch frames for the SwiftUI player container.
@available(iOS 17.0, *)
extension PlayerStateManager {
    /// Called by a tapped video row before `load` so the player can grow from that thumbnail.
    /// A video ID guards against a stale row gesture launching a different queued item.
    func prepareLaunch(for videoID: String, from frame: CGRect) {
        guard frame.width > 20, frame.height > 20,
              frame.width.isFinite, frame.height.isFinite,
              frame.origin.x.isFinite, frame.origin.y.isFinite else {
            pendingLaunchSource = nil
            return
        }
        pendingLaunchSource = (videoID, frame)
    }

    func finishLaunchPresentation() {
        launchSourceFrame = nil
    }

    func requestPlayerCollapse(then completion: (() -> Void)? = nil) {
        guard fullScreenPresented else {
            completion?()
            return
        }
        if let completion {
            pendingCollapseCompletion = (playbackSessionID, completion)
        }
        playerCollapseRequest &+= 1
    }

    func finishPlayerCollapse() {
        let completion = pendingCollapseCompletion
        pendingCollapseCompletion = nil
        if let completion, completion.sessionID == playbackSessionID, miniPlayerVisible {
            completion.action()
        }
    }

    func resizeFloatingMiniPlayer(to width: CGFloat) {
        guard width.isFinite else { return }
        floatingMiniPlayerWidth = width
        if preferences.rememberFloatingPlayerPlacement {
            preferences.savedFloatingPlayerWidth = Double(width)
        }
    }

    /// Stages one frame at the tapped thumbnail before expansion. `AVPlayerViewController` does
    /// not reliably participate in a SwiftUI insertion transition; the mounted surface must have
    /// a real starting frame. Actions without a thumbnail retain the floating-window fallback.
    func presentPlayer(for videoID: String, expanded: Bool) {
        playerPresentationTask?.cancel()
        let source = pendingLaunchSource?.videoID == videoID ? pendingLaunchSource?.frame : nil
        pendingLaunchSource = nil
        let wasVisible = miniPlayerVisible
        miniPlayerVisible = true
        guard expanded else {
            launchSourceFrame = nil
            return
        }

        // Already expanded: changing the current item must not replay the presentation animation.
        guard !fullScreenPresented else {
            launchSourceFrame = nil
            return
        }

        launchSourceFrame = source

        if wasVisible && source == nil {
            playerExpansionRequest &+= 1
            return
        }

        fullScreenPresented = false
        playerPresentationTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(16))
            guard !Task.isCancelled,
                  let self,
                  self.miniPlayerVisible,
                  self.currentVideo?.id == videoID else { return }
            self.playerExpansionRequest &+= 1
        }
    }

}
