import SwiftUI

/// Stable, explicitly-presented caption picker. Unlike `Menu`, its presentation state is owned by
/// this view and cannot be reset by the player's frequent elapsed-time updates.
@available(iOS 17.0, *)
struct CaptionPlayerMenu: View {
    let tracks: [VideoCaptionTrack]
    let selectedTrackID: String?
    let isLoading: Bool
    let onSelect: (VideoCaptionTrack?) -> Void
    let onPresentationChanged: (Bool) -> Void

    @State private var isPresented = false

    var body: some View {
        Button {
            onPresentationChanged(true)
            isPresented = true
        } label: {
            Image(systemName: selectedTrackID == nil ? "captions.bubble" : "captions.bubble.fill")
                .playerTopControl()
        }
        .accessibilityLabel("Captions")
        .accessibilityValue(selectedTrackID == nil ? "Off" : "On")
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Captions")
                    .font(.headline)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                Divider()

                ScrollView {
                    LazyVStack(spacing: 0) {
                        captionRow(title: "Off", id: nil)
                        if tracks.isEmpty {
                            Text("Captions unavailable")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                        } else {
                            ForEach(tracks) { track in
                                captionRow(title: track.displayName, id: track.id) {
                                    onSelect(track)
                                }
                            }
                        }
                    }
                }
            }
            .frame(minWidth: 250, idealWidth: 290, maxHeight: 360)
            .presentationCompactAdaptation(.popover)
        }
        .onChange(of: isPresented) { _, presented in
            if !presented {
                onPresentationChanged(false)
            }
        }
    }

    @ViewBuilder
    private func captionRow(
        title: String,
        id: String?,
        action: (() -> Void)? = nil
    ) -> some View {
        Button {
            if let action {
                action()
            } else {
                onSelect(nil)
            }
            isPresented = false
        } label: {
            HStack(spacing: 10) {
                Text(title)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if selectedTrackID == id {
                    if isLoading, id != nil {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.tint)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
