import SwiftUI

@available(iOS 17.0, *)
struct SponsorBlockSkipOverlay: View {
    let notice: SponsorBlockNotice
    let onUndo: () -> Void
    let onSkip: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack {
            Spacer()
            HStack(spacing: 12) {
                Image(systemName: notice.kind == .skipped ? "forward.fill" : "sparkles")
                    .foregroundStyle(categoryColor)
                Text(message)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Button(actionTitle, action: action)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(categoryColor)
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Dismiss")
            }
            .font(.caption)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.black.opacity(0.68), in: Capsule())
            .padding(.bottom, 20)
        }
        .padding(.horizontal)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var message: String {
        switch notice.kind {
        case .skipped: return "\(notice.category.displayName) skipped"
        case .prompt:
            return notice.category == .highlight
                ? "Jump to highlight?"
                : "Skip \(notice.category.displayName.lowercased())?"
        }
    }

    private var actionTitle: String {
        notice.kind == .skipped ? "Undo" : "Skip"
    }

    private var action: () -> Void {
        notice.kind == .skipped ? onUndo : onSkip
    }

    private var categoryColor: Color {
        switch notice.category {
        case .sponsor: return .green
        case .selfPromotion: return .yellow
        case .interaction: return .pink
        case .intro: return .cyan
        case .outro: return .blue
        case .highlight: return .purple
        }
    }
}
