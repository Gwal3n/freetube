import SwiftUI

/// A brief, non-modal acknowledgement shared by queue actions and playlist saving. The caller
/// owns timing and placement; this view keeps their typography, material, and transition equal.
@available(iOS 17.0, *)
struct TransientNoticePill: View {
    let title: Text
    let systemImage: String
    let onUndo: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            Label {
                title
            } icon: {
                Image(systemName: systemImage)
            }
            if let onUndo {
                Divider()
                    .frame(height: 18)
                Button("Undo", action: onUndo)
                    .fontWeight(.semibold)
                    .buttonStyle(.plain)
            }
        }
        .lineLimit(1)
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, 15)
        .padding(.vertical, 9)
        .fixedSize(horizontal: true, vertical: false)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().stroke(.primary.opacity(0.10), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.14), radius: 8, y: 3)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
