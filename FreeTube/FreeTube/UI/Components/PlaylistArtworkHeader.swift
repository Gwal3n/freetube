import SwiftUI

import Kingfisher

/// Shared public/local playlist artwork: full-width image, lower scrim and overlaid actions.
@available(iOS 17.0, *)
struct PlaylistArtworkHeader<Actions: View>: View {
    let thumbnailURL: URL?
    let actions: () -> Actions

    init(thumbnailURL: URL?, @ViewBuilder actions: @escaping () -> Actions) {
        self.thumbnailURL = thumbnailURL
        self.actions = actions
    }

    var body: some View {
        GeometryReader { geometry in
            KFImage(thumbnailURL)
                .thumbnail(size: CGSize(width: 500, height: 281)) {
                    MediaStyle.placeholderFill
                        .overlay { Image(systemName: "play.rectangle").foregroundStyle(.secondary) }
                }
                .resizable()
                .scaledToFill()
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
                .overlay(alignment: .bottom) {
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.65)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 100)
                }
                .overlay(alignment: .bottom) {
                    actions()
                        .padding(.bottom, 12)
                }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
    }
}
