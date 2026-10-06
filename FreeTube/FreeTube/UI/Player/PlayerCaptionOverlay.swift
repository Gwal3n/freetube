import AVFoundation
import SwiftUI

/// A leaf timeline view so caption changes do not redraw the transport or player container.
/// It samples the AVPlayer item's actual time, including pauses and seeks, every tenth of a second.
@available(iOS 17.0, *)
struct PlayerCaptionOverlay: View {
    let player: AVPlayer
    let cues: [VideoCaptionCue]
    let bottomPadding: CGFloat

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { _ in
            let time = player.currentTime().seconds
            VStack {
                Spacer(minLength: 0)
                if time.isFinite, let cue = currentCue(at: time) {
                    Text(verbatim: cue.text)
                        .font(.headline.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                        .lineLimit(3)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 6))
                        .padding(.horizontal, 20)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.bottom, bottomPadding)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func currentCue(at time: TimeInterval) -> VideoCaptionCue? {
        var lower = 0
        var upper = cues.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if cues[middle].startTime <= time {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        guard lower > 0 else { return nil }
        let cue = cues[lower - 1]
        return time < cue.endTime ? cue : nil
    }
}
