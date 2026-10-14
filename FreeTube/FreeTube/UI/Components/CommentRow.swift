import SwiftUI
import UIKit

struct CommentRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let comment: Comment
    var repliesTitle: String? = nil
    var repliesExpanded = false
    var onToggleReplies: (() -> Void)? = nil
    var onSeek: ((TimeInterval) -> Void)? = nil
    @State private var isBodyExpanded = false

    private var isLongComment: Bool {
        comment.bodyText.count > 240 || comment.bodyText.filter(\.isNewline).count >= 3
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(comment.authorName).appFont(.caption, weight: .semibold)
                Text(comment.publishedRelative).appFont(.caption2).foregroundStyle(.secondary)
            }
            SelectableCommentText(
                text: comment.bodyText,
                maximumNumberOfLines: isLongComment && !isBodyExpanded ? 3 : 0,
                onSeek: onSeek
            )

            if isLongComment {
                Button(isBodyExpanded ? "Show less" : "Read more") {
                    withAnimation(reduceMotion ? nil : InterfaceMotion.content) {
                        isBodyExpanded.toggle()
                    }
                }
                .appFont(.caption, weight: .semibold)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            HStack(spacing: 16) {
                Label("\(comment.likeCount)", systemImage: "hand.thumbsup")
                    .labelStyle(.titleAndIcon)
                    .appFont(.caption)
                if let repliesTitle, let onToggleReplies {
                    Button(action: onToggleReplies) {
                        HStack(spacing: 4) {
                            Image(systemName: repliesExpanded ? "chevron.up" : "chevron.down")
                            Text(repliesTitle)
                        }
                        .appFont(.caption)
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
    @Environment(\.appFontPreset) private var preset
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let text: String
    let maximumNumberOfLines: Int
    let onSeek: ((TimeInterval) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.backgroundColor = .clear
        view.isEditable = false
        view.isSelectable = true
        view.isScrollEnabled = false
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.adjustsFontForContentSizeCategory = true
        view.dataDetectorTypes = []
        view.linkTextAttributes = [.foregroundColor: UIColor.systemBlue]
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.required, for: .vertical)
        view.delegate = context.coordinator
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.onSeek = onSeek
        let font = preset.uiFont(style: .subheadline, size: 15)
        if context.coordinator.lastText != text || context.coordinator.lastPreset != preset
            || context.coordinator.lastDynamicTypeSize != dynamicTypeSize
            || context.coordinator.lastHasSeek != (onSeek != nil) {
            let rendered = NSMutableAttributedString(string: text, attributes: [
                .font: font,
                .foregroundColor: UIColor.label
            ])
            if onSeek != nil {
                for match in CommentTimestampLinks.matches(in: text) {
                    guard let url = URL(string: "freetube-seek://\(Int(match.seconds))") else { continue }
                    rendered.addAttributes([
                        .link: url,
                        .foregroundColor: UIColor.systemBlue
                    ], range: match.range)
                }
            }
            view.attributedText = rendered
            context.coordinator.lastText = text
            context.coordinator.lastPreset = preset
            context.coordinator.lastDynamicTypeSize = dynamicTypeSize
            context.coordinator.lastHasSeek = onSeek != nil
        }
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

    final class Coordinator: NSObject, UITextViewDelegate {
        var onSeek: ((TimeInterval) -> Void)?
        var lastText: String?
        var lastPreset: AppFontPreset?
        var lastDynamicTypeSize: DynamicTypeSize?
        var lastHasSeek = false

        func textView(
            _ textView: UITextView,
            shouldInteractWith url: URL,
            in characterRange: NSRange,
            interaction: UITextItemInteraction
        ) -> Bool {
            guard url.scheme == "freetube-seek",
                  let seconds = TimeInterval(url.host ?? "") else { return true }
            onSeek?(seconds)
            return false
        }
    }
}
