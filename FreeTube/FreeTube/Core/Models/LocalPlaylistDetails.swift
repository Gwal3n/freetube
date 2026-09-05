import Foundation

struct LocalPlaylistDetails: Sendable {
    let playlist: LocalPlaylistSnapshot
    let videos: [Video]
}
