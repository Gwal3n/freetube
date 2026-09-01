import SwiftUI

@available(iOS 17.0, *)
struct SponsorBlockSkipOverlay: View {
    let notice: SponsorBlockNotice
    let onUndo: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack {
            Spacer()
            HStack(spacing: 12) {
                Image(systemName: "forward.fill")
                    .foregroundStyle(.green)
                Text("\(notice.category.displayName) skipped")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Button("Undo", action: onUndo)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.green)
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Dismiss")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.black.opacity(0.88), in: Capsule())
            .padding(.bottom, 64)
        }
        .padding(.horizontal)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
