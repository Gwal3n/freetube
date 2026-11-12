import Foundation
import XCTest
@testable import FreeTube

@MainActor
final class MusicSearchDecodingTests: XCTestCase {
    func testDecodesTopResultSongsArtistsAndPlaylistsWhileSkippingAlbums() throws {
        let root = try JSONSerialization.jsonObject(with: Data(Self.fixture.utf8))
        let hits = MusicSearchService.decode(root)

        XCTAssertEqual(hits.map(\.id), ["v:topVideo01", "v:songVideo1", "c:UCartist", "p:PLmix"])

        guard case .video(let top) = hits[0] else { return XCTFail("Expected top video") }
        XCTAssertEqual(top.title, "Von dutch")
        XCTAssertEqual(top.channelID, "UCartist")
        XCTAssertEqual(top.channelName, "Charli xcx")
        XCTAssertEqual(top.viewCount, 43_000_000)
        XCTAssertEqual(top.duration, 265)

        guard case .video(let song) = hits[1] else { return XCTFail("Expected song") }
        XCTAssertEqual(song.channelName, "Charli xcx")
        XCTAssertEqual(song.viewCount, 125_000_000)
        XCTAssertNil(song.duration)

        guard case .playlist(let playlist) = hits[3] else { return XCTFail("Expected playlist") }
        XCTAssertEqual(playlist.channelName, "YouTube Music")
        XCTAssertEqual(playlist.videoCount, 55)
    }

    private static let fixture = """
    {"contents":{"tabbedSearchResultsRenderer":{"tabs":[{"tabRenderer":{"content":{"sectionListRenderer":{"contents":[
      {"musicCardShelfRenderer":{
        "title":{"runs":[{"text":"Von dutch","navigationEndpoint":{"watchEndpoint":{"videoId":"topVideo01"}}}]},
        "subtitle":{"runs":[{"text":"Video"},{"text":" • "},
          {"text":"Charli xcx","navigationEndpoint":{"browseEndpoint":{"browseId":"UCartist"}}},
          {"text":" • "},{"text":"43M views"},{"text":" • "},{"text":"4:25"}]}}},
      {"itemSectionRenderer":{"contents":[
        {"musicResponsiveListItemRenderer":{
          "playlistItemData":{"videoId":"songVideo1"},
          "flexColumns":[
            {"musicResponsiveListItemFlexColumnRenderer":{"text":{"runs":[{"text":"360"}]}}},
            {"musicResponsiveListItemFlexColumnRenderer":{"text":{"runs":[{"text":"Song"},{"text":" • "},
              {"text":"Charli xcx","navigationEndpoint":{"browseEndpoint":{"browseId":"UCartist"}}}]}}},
            {"musicResponsiveListItemFlexColumnRenderer":{"text":{"runs":[{"text":"125M plays"}]}}}]}},
        {"musicResponsiveListItemRenderer":{
          "navigationEndpoint":{"browseEndpoint":{"browseId":"UCartist"}},
          "flexColumns":[
            {"musicResponsiveListItemFlexColumnRenderer":{"text":{"runs":[{"text":"Charli xcx"}]}}},
            {"musicResponsiveListItemFlexColumnRenderer":{"text":{"runs":[{"text":"Artist"},{"text":" • "},{"text":"10M monthly audience"}]}}}]}},
        {"musicResponsiveListItemRenderer":{
          "navigationEndpoint":{"browseEndpoint":{"browseId":"MPREb_album"}},
          "flexColumns":[
            {"musicResponsiveListItemFlexColumnRenderer":{"text":{"runs":[{"text":"BRAT"}]}}}]}},
        {"musicResponsiveListItemRenderer":{
          "navigationEndpoint":{"browseEndpoint":{"browseId":"VLPLmix"}},
          "flexColumns":[
            {"musicResponsiveListItemFlexColumnRenderer":{"text":{"runs":[{"text":"Brat Mix"}]}}},
            {"musicResponsiveListItemFlexColumnRenderer":{"text":{"runs":[{"text":"Playlist"},{"text":" • "},
              {"text":"YouTube Music"},{"text":" • "},{"text":"55 songs"}]}}}]}}
      ]}}
    ]}}}}]}}}
    """
}
