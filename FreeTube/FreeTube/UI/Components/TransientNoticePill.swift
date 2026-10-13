import SwiftUI

/// A brief, non-modal acknowledgement shared by queue actions and playlist saving. The caller
/// owns timing and placement; this view keeps their typography, material, and transition equal.
@available(iOS 17.0, *)
struct TransientNoticePill: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let title: Text
    let systemImage: String
    let onUndo: (() -> Void)?

    var body: some View {
        ViewThatFits(in: .horizontal) {
            noticeContent
                .fixedSize(horizontal: true, vertical: false)
            noticeContent
                .frame(maxWidth: .infinity)
        }
        .font(.subheadline.weight(.semibold))
        .background(.regularMaterial, in: noticeShape)
        .overlay(noticeShape.stroke(.primary.opacity(0.10), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.14), radius: 8, y: 3)
        .padding(.horizontal, 16)
        .transition(.opacity.combined(with: .offset(y: 8)))
    }

    private var noticeContent: some View {
        HStack(spacing: 10) {
            Label {
                title
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                    .minimumScaleFactor(0.85)
            } icon: {
                Image(systemName: systemImage)
            }
            .layoutPriority(1)
            if let onUndo {
                Divider()
                    .frame(height: 18)
                Button("Undo", action: onUndo)
                    .fontWeight(.semibold)
                    .frame(minWidth: MediaStyle.actionSize, minHeight: MediaStyle.actionSize)
                    .contentShape(Rectangle())
                    .buttonStyle(.plain)
            }
        }
        .padding(.leading, 15)
        .padding(.trailing, onUndo == nil ? 15 : 8)
        .padding(.vertical, onUndo == nil ? 9 : 0)
        .frame(minHeight: MediaStyle.actionSize)
    }

    private var noticeShape: RoundedRectangle {
        RoundedRectangle(
            cornerRadius: dynamicTypeSize.isAccessibilitySize ? 18 : 999,
            style: .continuous
        )
    }
}
