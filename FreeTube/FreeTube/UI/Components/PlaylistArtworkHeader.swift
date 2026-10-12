import SwiftUI
import UIKit

import Kingfisher

/// Shared public/local playlist artwork: full-width image, lower scrim and overlaid actions.
@available(iOS 17.0, *)
struct PlaylistArtworkHeader<Actions: View>: View {
    let thumbnailURL: URL?
    let imageData: Data?
    let actions: () -> Actions

    init(thumbnailURL: URL?, imageData: Data? = nil, @ViewBuilder actions: @escaping () -> Actions) {
        self.thumbnailURL = thumbnailURL
        self.imageData = imageData
        self.actions = actions
    }

    var body: some View {
        GeometryReader { geometry in
            artwork
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

    @ViewBuilder
    private var artwork: some View {
        if let imageData, let image = UIImage(data: imageData) {
            Image(uiImage: image).resizable()
        } else {
            KFImage(thumbnailURL)
                .thumbnail(size: CGSize(width: 500, height: 281)) {
                    MediaStyle.placeholderFill
                        .overlay { Image(systemName: "play.rectangle").foregroundStyle(.secondary) }
                }
                .resizable()
        }
    }
}
