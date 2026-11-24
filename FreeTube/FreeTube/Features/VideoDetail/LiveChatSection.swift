import SwiftUI

/// Comments-slot control for live videos. Tapping opens the chapter-style live chat sheet.
@available(iOS 17.0, *)
struct LiveChatSection: View {
    let onOpen: () -> Void

    @Environment(PlayerStateManager.self) private var player
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isPresented: Bool { player.liveChatPresented }

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 0) {
                PlayerSectionHeading(
                    title: "Live chat",
                    isExpanded: isPresented,
                    showsDisclosureIndicator: false
                )
                Image(systemName: isPresented ? "chevron.down" : "chevron.up")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: MediaStyle.actionSize, height: MediaStyle.actionSize)
                    .contentShape(Circle())
                    .animation(reduceMotion ? nil : InterfaceMotion.quick, value: isPresented)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(ResponsiveButtonStyle())
        .frame(minHeight: 44)
        .padding(.horizontal)
        .accessibilityLabel("Live chat")
        .accessibilityValue(isPresented ? "Open" : "Closed")
        .accessibilityHint(isPresented ? "Closes live chat" : "Opens live chat")
    }
}
