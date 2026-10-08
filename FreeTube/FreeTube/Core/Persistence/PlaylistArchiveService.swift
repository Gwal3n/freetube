import Foundation

/// Builds and restores selective playlist archives without requesting YouTube metadata again.
@available(iOS 17.0, *)
@MainActor
final class PlaylistArchiveService {
    private let playlists = LocalPlaylistService()

    /// Exports every local playlist in display order, or only the requested playlist.
    func makeArchive(playlistID: String? = nil) async throws -> PlaylistArchive {
        let allPlaylists = await playlists.playlists()
        let selected = allPlaylists.filter { playlistID == nil || $0.id == playlistID }
        guard !selected.isEmpty else { throw ArchiveError.noPlaylists }

        var records: [AppBackup.PlaylistRecord] = []
        for playlist in selected {
            guard let details = await playlists.details(id: playlist.id) else {
                throw ArchiveError.playlistUnavailable
            }
            records.append(AppBackup.PlaylistRecord(
                title: playlist.title,
                descriptionText: playlist.descriptionText,
                sourcePlaylistID: playlist.sourcePlaylistID,
                videos: details.videos
            ))
        }
        return PlaylistArchive(playlists: records)
    }

    func encode(_ archive: PlaylistArchive) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(archive)
    }

    func decode(_ data: Data) throws -> PlaylistArchive {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let archive = try decoder.decode(PlaylistArchive.self, from: data)
        guard archive.type == PlaylistArchive.fileType else { throw ArchiveError.invalidFile }
        guard archive.formatVersion == PlaylistArchive.currentVersion else {
            throw ArchiveError.unsupportedVersion
        }
        guard !archive.playlists.isEmpty else { throw ArchiveError.noPlaylists }
        return archive
    }

    /// Adds personal playlists as copies; a saved public playlist with the same source ID is
    /// updated in place. All other app data and playlists remain untouched.
    @discardableResult
    func importArchive(_ archive: PlaylistArchive) async throws -> Int {
        guard archive.type == PlaylistArchive.fileType else { throw ArchiveError.invalidFile }
        guard archive.formatVersion == PlaylistArchive.currentVersion else {
            throw ArchiveError.unsupportedVersion
        }
        guard !archive.playlists.isEmpty else { throw ArchiveError.noPlaylists }

        for record in archive.playlists {
            _ = await LocalPlaylistWriter.shared.replace(
                title: record.title,
                descriptionText: record.descriptionText,
                sourcePlaylistID: record.sourcePlaylistID,
                videos: record.videos
            )
        }
        return archive.playlists.count
    }

    enum ArchiveError: LocalizedError {
        case invalidFile
        case unsupportedVersion
        case noPlaylists
        case playlistUnavailable

        var errorDescription: String? {
            switch self {
            case .invalidFile: "This is not a FreeTube playlist archive."
            case .unsupportedVersion: "This playlist archive uses an unsupported format."
            case .noPlaylists: "There are no playlists to export or import."
            case .playlistUnavailable: "A playlist could not be read. Please try again."
            }
        }
    }
}
