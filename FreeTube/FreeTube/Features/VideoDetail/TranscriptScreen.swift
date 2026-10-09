import SwiftUI

/// A searchable, read-only view of the selected caption track. Cue loading stays in the player
/// caption model; opening the transcript does not add another extraction or network path.
@available(iOS 17.0, *)
struct TranscriptScreen: View {
    let captionsModel: PlayerCaptionsModel
    let onSeek: (TimeInterval) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            Group {
                if captionsModel.isLoadingCues {
                    ProgressView("Loading transcript…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if captionsModel.hasCueError {
                    ContentUnavailableView {
                        Label("Transcript unavailable", systemImage: "text.bubble")
                    } description: {
                        Text("The captions could not be loaded.")
                    } actions: {
                        Button("Retry") { captionsModel.retrySelectedTrack() }
                    }
                } else if captionsModel.cues.isEmpty {
                    ContentUnavailableView(
                        "No transcript available",
                        systemImage: "text.bubble"
                    )
                } else if filteredCues.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    List {
                        ForEach(Array(filteredCues.enumerated()), id: \.offset) { entry in
                            let cue = entry.element
                            Button {
                                onSeek(cue.startTime)
                                dismiss()
                            } label: {
                                HStack(alignment: .firstTextBaseline, spacing: 16) {
                                    Text(verbatim: timestamp(for: cue.startTime))
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                        .frame(minWidth: 48, alignment: .leading)
                                    Text(verbatim: cue.text)
                                        .foregroundStyle(.primary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(.vertical, 4)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text(verbatim: "\(timestamp(for: cue.startTime)), \(cue.text)"))
                            .accessibilityHint("Jump to this point in the video")
                        }
                    }
                }
            }
            .navigationTitle("Transcript")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .searchable(text: $searchText, prompt: "Search transcript")
        }
    }

    private var filteredCues: [VideoCaptionCue] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return captionsModel.cues }
        return captionsModel.cues.filter { $0.text.localizedStandardContains(query) }
    }

    private func timestamp(for seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.isFinite ? seconds : 0))
        let minutes = total / 60
        let remainder = total % 60
        if minutes >= 60 {
            return String(format: "%d:%02d:%02d", minutes / 60, minutes % 60, remainder)
        }
        return String(format: "%d:%02d", minutes, remainder)
    }
}
