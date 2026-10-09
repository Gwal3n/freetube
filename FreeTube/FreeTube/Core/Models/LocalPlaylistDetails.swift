import Foundation

struct LocalPlaylistDetails: Sendable {
    let playlist: LocalPlaylistSnapshot
    let videos: [Video]
}

extension LocalPlaylistDetails {
    /// The same playlist identity and order used by its Library screen and History restoration.
    var playbackDetails: PlaylistDetails {
        PlaylistDetails(
            playlist: Playlist(
                id: "local:\(playlist.id)", title: playlist.title,
                channelID: nil, channelName: nil, thumbnailURL: playlist.thumbnailURL,
                videoCount: playlist.videoCount,
                descriptionText: playlist.descriptionText,
                isOwnedByUser: true
            ),
            videos: videos,
            continuationToken: nil
        )
    }
}
