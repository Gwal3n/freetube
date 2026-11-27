import SwiftUI

/// Small, opt-in preview. Only this leaf observes the playback clock; the comment list itself
/// does not rebuild on every player tick.
@available(iOS 17.0, *)
struct FeaturedCommentPreview: View {
    @Environment(PlayerStateManager.self) private var player
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hiddenAuthors = HiddenCommentAuthorsStore.shared

    let model: CommentsViewModel
    let onlyNearPlayback: Bool
    let onOpen: (String?) -> Void

    var body: some View {
        _ = hiddenAuthors.revision
        let timed = model.featuredComment(near: player.elapsed)
        let timedVisible = timed.flatMap { hiddenAuthors.hides($0.comment) ? nil : $0 }
        let excerpt = timedVisible?.comment.bodyText ?? (onlyNearPlayback ? nil : model.teaserText) ?? ""
        Group {
            if !excerpt.isEmpty {
                Button {
                    onOpen(timedVisible?.comment.id)
                } label: {
                    HStack(alignment: .top, spacing: 8) {
                        Text(excerpt)
                            .font(.subheadline)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if let timedVisible {
                            Text(formattedTime(timedVisible.time))
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
        .animation(reduceMotion ? nil : InterfaceMotion.content, value: timedVisible?.comment.id)
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
