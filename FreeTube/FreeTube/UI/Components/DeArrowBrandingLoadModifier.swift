import SwiftUI

/// Runs a visible video's optional DeArrow work without making its row a nested menu source.
/// List rows own their model so the native context menu attaches to the outer scrolling cell.
@available(iOS 17.0, *)
struct DeArrowBrandingLoadModifier: ViewModifier {
    let video: Video
    let model: DeArrowVideoViewModel
    @AppStorage("com.leshko.freetube.deArrowTitles") private var replaceTitles = false
    @AppStorage("com.leshko.freetube.deArrowThumbnails") private var replaceThumbnails = false
    @AppStorage("com.leshko.freetube.deArrowRandomThumbnails") private var randomFallback = true

    func body(content: Content) -> some View {
        content
            .task(id: "\(video.id)|\(replaceTitles)|\(replaceThumbnails)|\(randomFallback)|\(video.duration ?? 0)|\(video.isLive)") {
                await model.load(video: video, replaceTitles: replaceTitles,
                                 replaceThumbnails: replaceThumbnails, randomFallback: randomFallback)
            }
    }
}

@available(iOS 17.0, *)
extension View {
    func loadDeArrowBranding(video: Video, model: DeArrowVideoViewModel) -> some View {
        modifier(DeArrowBrandingLoadModifier(video: video, model: model))
    }
}
