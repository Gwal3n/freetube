import SwiftUI
import UIKit

struct CommentRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let comment: Comment
    var repliesTitle: String? = nil
    var repliesExpanded = false
    var onToggleReplies: (() -> Void)? = nil
    @State private var isBodyExpanded = false

    private var isLongComment: Bool {
        comment.bodyText.count > 240 || comment.bodyText.filter(\.isNewline).count >= 3
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(comment.authorName).font(.caption.weight(.semibold))
                Text(comment.publishedRelative).font(.caption2).foregroundStyle(.secondary)
            }
            SelectableCommentText(
                text: comment.bodyText,
                maximumNumberOfLines: isLongComment && !isBodyExpanded ? 3 : 0
            )

            if isLongComment {
                Button(isBodyExpanded ? "Show less" : "Read more") {
                    withAnimation(reduceMotion ? nil : InterfaceMotion.content) {
                        isBodyExpanded.toggle()
                    }
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            HStack(spacing: 16) {
                Label("\(comment.likeCount)", systemImage: "hand.thumbsup")
                    .labelStyle(.titleAndIcon)
                    .font(.caption)
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

/// UIKit-backed text is used deliberately here: SwiftUI's `.textSelection` on iPhone presents a
/// whole-value Copy/Share menu, while a non-editable `UITextView` provides the familiar selection
/// handles for choosing an exact sentence. Scrolling remains owned by the surrounding player feed.
private struct SelectableCommentText: UIViewRepresentable {
    let text: String
    let maximumNumberOfLines: Int

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.backgroundColor = .clear
        view.isEditable = false
        view.isSelectable = true
        view.isScrollEnabled = false
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.adjustsFontForContentSizeCategory = true
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.required, for: .vertical)
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        if view.text != text { view.text = text }
        view.font = .preferredFont(forTextStyle: .subheadline)
        view.textColor = .label
        view.textContainer.maximumNumberOfLines = maximumNumberOfLines
        view.textContainer.lineBreakMode = maximumNumberOfLines == 0
            ? .byWordWrapping
            : .byTruncatingTail
        view.invalidateIntrinsicContentSize()
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: UITextView,
        context: Context
    ) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        let measured = uiView.sizeThatFits(
            CGSize(width: width, height: .greatestFiniteMagnitude)
        )
        return CGSize(width: width, height: ceil(measured.height))
    }
}
