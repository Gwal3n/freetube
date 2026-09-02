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
            HStack {
                HStack(spacing: 6) {
                    Button(action: action) {
                        HStack(spacing: 6) {
                            Image(systemName: notice.kind == .skipped ? "arrow.uturn.backward" : "sparkles")
                                .foregroundStyle(categoryColor)
                            Text(message)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                        }
                        .padding(.leading, 9)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(actionAccessibilityLabel)

                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                    }
                    .accessibilityLabel("Dismiss")
                }
                .background(.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 8))

                Spacer(minLength: 0)
            }
            .padding(.bottom, 20)
        }
        .padding(.leading, 10)
        .padding(.trailing, 40)
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

    private var actionAccessibilityLabel: String {
        notice.kind == .skipped ? "Undo sponsor skip" : "Skip to highlight"
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
