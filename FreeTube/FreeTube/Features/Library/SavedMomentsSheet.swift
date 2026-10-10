import SwiftUI

/// Video-scoped saved moments presented from a playlist or a video's actions.
@available(iOS 17.0, *)
struct SavedMomentsSheet: View {
    let video: Video
    let onOpenVideo: (Video) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            SavedMomentsScreen(videoID: video.id) { _ in
                dismiss()
                onOpenVideo(video)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
