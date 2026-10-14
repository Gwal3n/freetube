import SwiftUI

/// Small, opt-in preview. Only this leaf observes the playback clock; the comment list itself
/// does not rebuild on every player tick.
@available(iOS 17.0, *)
struct FeaturedCommentPreview: View {
    @Environment(PlayerStateManager.self) private var player

    let model: CommentsViewModel
    let onOpen: (String?) -> Void

    var body: some View {
        let timed = model.featuredComment(near: player.elapsed)
        let excerpt = timed?.comment.bodyText ?? model.teaserText ?? ""
        if !excerpt.isEmpty {
            Button {
                onOpen(timed?.comment.id)
            } label: {
                HStack(alignment: .top, spacing: 8) {
                    Text(excerpt)
                        .font(.subheadline)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let timed {
                        Text(formattedTime(timed.time))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)
                            .fixedSize()
                    }
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.bottom, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(ResponsiveButtonStyle())
            .accessibilityHint("Opens comments")
            .transition(.opacity)
        }
    }

    private func formattedTime(_ seconds: TimeInterval) -> String {
        let value = Int(seconds)
        let hours = value / 3600
        let minutes = value / 60 % 60
        let remaining = value % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, remaining)
            : String(format: "%d:%02d", minutes, remaining)
    }
}
