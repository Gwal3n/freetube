import SwiftUI

/// Attaches opt-in, cancellable branding work to a visible video without moving networking into
/// the view. The per-row model prevents one video's response from redrawing an entire feed.
@available(iOS 17.0, *)
struct DeArrowVideoContent<Content: View>: View {
    let video: Video
    let content: (DeArrowVideoViewModel) -> Content
    @State private var model = DeArrowVideoViewModel()
    @AppStorage("com.leshko.freetube.deArrowTitles") private var replaceTitles = false
    @AppStorage("com.leshko.freetube.deArrowThumbnails") private var replaceThumbnails = false
    @AppStorage("com.leshko.freetube.deArrowRandomThumbnails") private var randomFallback = true

    init(video: Video, @ViewBuilder content: @escaping (DeArrowVideoViewModel) -> Content) {
        self.video = video
        self.content = content
    }

    var body: some View {
        content(model)
            .task(id: "\(video.id)|\(replaceTitles)|\(replaceThumbnails)|\(randomFallback)|\(video.duration ?? 0)|\(video.isLive)") {
                await model.load(video: video, replaceTitles: replaceTitles,
                                 replaceThumbnails: replaceThumbnails, randomFallback: randomFallback)
            }
    }
}
