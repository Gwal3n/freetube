import SwiftUI

struct CommentRow: View {
    let comment: Comment
    var onLike: () -> Void = {}
    var repliesTitle: String? = nil
    var repliesExpanded = false
    var onToggleReplies: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(comment.authorName).font(.caption.weight(.semibold))
                Text(comment.publishedRelative).font(.caption2).foregroundStyle(.secondary)
            }
            Text(comment.bodyText).font(.subheadline)

            HStack(spacing: 16) {
                Button(action: onLike) {
                    Label("\(comment.likeCount)", systemImage: comment.isLikedByUser ? "hand.thumbsup.fill" : "hand.thumbsup")
                        .labelStyle(.titleAndIcon)
                        .font(.caption)
                }
                if let repliesTitle, let onToggleReplies {
                    Button(action: onToggleReplies) {
                        HStack(spacing: 4) {
                            Image(systemName: repliesExpanded ? "chevron.up" : "chevron.down")
                            Text(repliesTitle)
                        }
                        .font(.caption)
                    }
                    .foregroundStyle(.primary)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }
}
