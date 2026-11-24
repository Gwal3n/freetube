import SwiftUI

@available(iOS 17.0, *)
struct LiveChatRow: View {
    let message: LiveChatMessage

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.kind != .system {
                Text(verbatim: message.authorName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(authorColor)
                    .lineLimit(1)
            }
            Text(message.text)
                .font(.subheadline)
                .foregroundStyle(message.kind == .system ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let amount = message.amountText, !amount.isEmpty {
                Text(verbatim: amount)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.yellow)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
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
