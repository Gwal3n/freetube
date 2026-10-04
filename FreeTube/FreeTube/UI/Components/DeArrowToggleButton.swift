import SwiftUI

/// A subtle branding switch with a full-size touch target, kept separate from playback.
@available(iOS 17.0, *)
struct DeArrowToggleButton: View {
    let video: Video
    let model: DeArrowVideoViewModel
    var onThumbnail = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if model.hasReplacement(for: video) {
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.15)) {
                    model.toggleOriginal(for: video)
                }
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: onThumbnail ? 11 : 10, weight: .semibold))
                    .foregroundStyle(onThumbnail
                        ? Color.white.opacity(0.88)
                        : Color.secondary.opacity(model.showsOriginal(for: video) ? 0.55 : 0.72))
                    .shadow(color: onThumbnail ? .black.opacity(0.9) : .clear,
                            radius: onThumbnail ? 2 : 0, y: 1)
                    .padding(onThumbnail ? 6 : 0)
                    .frame(width: MediaStyle.actionSize, height: MediaStyle.actionSize,
                           alignment: onThumbnail ? .topTrailing : .center)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(model.showsOriginal(for: video) ? "Show DeArrow title and thumbnail" : "Show original title and thumbnail")
        }
    }
}
