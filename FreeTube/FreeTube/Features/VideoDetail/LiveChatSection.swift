import SwiftUI

/// Collapsed-by-default live chat in the player panel. Polls only while expanded.
@available(iOS 17.0, *)
struct LiveChatSection: View {
    @State private var model: LiveChatViewModel
    @State private var isExpanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    init(videoID: String) {
        _model = State(wrappedValue: LiveChatViewModel(videoID: videoID))
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 8) {
            header
            if isExpanded {
                chatContent
            }
        }
        .clipped()
        .errorToast(Bindable(model).errorState)
        .onChange(of: isExpanded) { _, expanded in
            if expanded {
                model.startPolling()
            } else {
                model.stopPolling()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard isExpanded else { return }
            if phase == .active {
                model.startPolling()
            } else {
                model.stopPolling()
            }
        }
        .onDisappear {
            model.stopPolling()
        }
    }

    private var header: some View {
        Button {
            withAnimation(reduceMotion ? nil : InterfaceMotion.content) {
                isExpanded.toggle()
            }
        } label: {
            PlayerSectionHeading(
                title: "Live chat",
                detail: model.isPolling ? String(localized: "Live") : nil,
                isExpanded: isExpanded
            )
            .padding(.horizontal)
        }
        .buttonStyle(ResponsiveButtonStyle())
    }

    @ViewBuilder
    private var chatContent: some View {
        if model.chatUnavailable {
            Text("Live chat isn’t available for this stream.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
        } else if model.isLoading && model.messages.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        } else if model.messages.isEmpty && model.chatEnded {
            Text("Live chat has ended.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
        } else if model.messages.isEmpty {
            Text("Waiting for messages…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
        } else {
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(model.messages) { message in
                    LiveChatRow(message: message)
                }
            }
            if model.chatEnded {
                Text("Live chat has ended.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        }
    }
}
