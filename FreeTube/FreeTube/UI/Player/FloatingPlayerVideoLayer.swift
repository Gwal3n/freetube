import SwiftUI
import AVFoundation
import UIKit

/// A passive second display layer for the existing AVQueuePlayer. It never creates or owns an
/// AVPlayerItem, and the AVPlayerViewController remains mounted for expanded playback and PiP.
@available(iOS 17.0, *)
struct FloatingPlayerVideoLayer: UIViewRepresentable {
    let player: AVPlayer
    var fillsFrame = false

    final class LayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }

        var playerLayer: AVPlayerLayer? { layer as? AVPlayerLayer }
    }

    func makeUIView(context: Context) -> LayerView {
        let view = LayerView()
        view.backgroundColor = .black
        view.isUserInteractionEnabled = false
        view.accessibilityElementsHidden = true
        view.playerLayer?.videoGravity = fillsFrame ? .resizeAspectFill : .resizeAspect
        view.playerLayer?.player = player
        return view
    }

    func updateUIView(_ view: LayerView, context: Context) {
        let gravity: AVLayerVideoGravity = fillsFrame ? .resizeAspectFill : .resizeAspect
        if view.playerLayer?.videoGravity != gravity {
            view.playerLayer?.videoGravity = gravity
        }
        if view.playerLayer?.player !== player {
            view.playerLayer?.player = player
        }
    }

    static func dismantleUIView(_ view: LayerView, coordinator: ()) {
        view.playerLayer?.player = nil
    }
}
