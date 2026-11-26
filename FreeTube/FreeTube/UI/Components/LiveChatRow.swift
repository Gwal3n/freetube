import SwiftUI

@available(iOS 17.0, *)
struct LiveChatRow: View {
    let message: LiveChatMessage
    var onOpenChannel: ((String) -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            messageContent
            if let amount = message.amountText, !amount.isEmpty {
                Text(verbatim: amount)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.yellow)
                    .lineLimit(1)
                    .textSelection(.enabled)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var messageContent: some View {
        if message.kind == .system {
            Text(message.text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        } else {
            // Single flowing paragraph: wrapped lines start at the leading edge, not under a
            // trailing text column beside the author name.
            (authorText + Text(verbatim: " \(message.text)")
                .font(.subheadline)
                .foregroundStyle(.primary))
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .overlay(alignment: .topLeading) {
                    authorHitTarget
                }
        }
    }

    private var authorText: Text {
        Text(verbatim: message.authorName)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(authorColor)
    }

    @ViewBuilder
    private var authorHitTarget: some View {
        if let channelID = message.authorChannelID,
           !channelID.isEmpty,
           let onOpenChannel {
            Text(verbatim: message.authorName)
                .font(.subheadline.weight(.semibold))
                .opacity(0.01)
                .onTapGesture { onOpenChannel(channelID) }
                .accessibilityHidden(true)
        }
    }

    private var authorColor: Color {
        switch message.kind {
        case .superChat, .sticker: .yellow
        case .membership: .green
        case .text, .system: .secondary
        }
    }

    @ViewBuilder
    private var background: some View {
        switch message.kind {
        case .superChat, .sticker:
            Color.yellow.opacity(0.12)
        case .membership:
            Color.green.opacity(0.10)
        case .text, .system:
            Color.clear
        }
    }

    private var accessibilityLabel: String {
        switch message.kind {
        case .system:
            return message.text
        case .superChat, .sticker:
            let amount = message.amountText.map { " \($0)" } ?? ""
            return "\(message.authorName)\(amount): \(message.text)"
        case .membership:
            return "\(message.authorName): \(message.text)"
        case .text:
            return "\(message.authorName): \(message.text)"
        }
    }
}
