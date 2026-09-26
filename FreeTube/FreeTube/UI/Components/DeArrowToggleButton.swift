import SwiftUI

/// An independent tap target above the thumbnail, not a button nested in the playback label.
@available(iOS 17.0, *)
struct DeArrowToggleButton: View {
    let video: Video
    let model: DeArrowVideoViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if model.hasReplacement(for: video) {
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.15)) {
                    model.toggleOriginal(for: video)
                }
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(model.showsOriginal(for: video) ? 0.65 : 1))
                    .frame(width: 22, height: 22)
                    .background(.black.opacity(0.55), in: Circle())
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(model.showsOriginal(for: video) ? "Show DeArrow title and thumbnail" : "Show original title and thumbnail")
        }
    }
}
