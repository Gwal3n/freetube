import SwiftUI

/// Equatable boundary keeps playback-time ticks from rebuilding an open native caption menu.
@available(iOS 17.0, *)
struct CaptionPlayerMenu: View, Equatable {
    let tracks: [VideoCaptionTrack]
    let selectedTrackID: String?
    let isLoading: Bool
    let onSelect: (VideoCaptionTrack?) -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.tracks == rhs.tracks
            && lhs.selectedTrackID == rhs.selectedTrackID
            && lhs.isLoading == rhs.isLoading
    }

    var body: some View {
        Menu {
            Button {
                onSelect(nil)
            } label: {
                if selectedTrackID == nil {
                    Label("Off", systemImage: "checkmark")
                } else {
                    Text("Off")
                }
            }

            if !tracks.isEmpty {
                Divider()
                ForEach(tracks) { track in
                    Button {
                        onSelect(track)
                    } label: {
                        if selectedTrackID == track.id {
                            Label(
                                track.displayName,
                                systemImage: isLoading ? "clock" : "checkmark"
                            )
                        } else {
                            Text(track.displayName)
                        }
                    }
                }
            }
        } label: {
            Image(systemName: selectedTrackID == nil ? "captions.bubble" : "captions.bubble.fill")
                .playerTopControl()
        }
        .disabled(tracks.isEmpty)
        .accessibilityLabel("Captions")
        .accessibilityValue(selectedTrackID == nil ? "Off" : "On")
    }
}
