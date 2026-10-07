import XCTest
import CoreGraphics
@testable import FreeTube

@MainActor
final class PlayerPolishTests: XCTestCase {
    func testSleepTimerOptionsHaveOnlyTimedDurationsWhereExpected() {
        XCTAssertNil(SleepTimerOption.off.duration)
        XCTAssertNil(SleepTimerOption.endOfVideo.duration)
        XCTAssertEqual(SleepTimerOption.fifteenMinutes.duration, Duration.seconds(15 * 60))
        XCTAssertEqual(SleepTimerOption.thirtyMinutes.duration, Duration.seconds(30 * 60))
        XCTAssertEqual(SleepTimerOption.oneHour.duration, Duration.seconds(60 * 60))
    }

    func testPlayerControlLayoutKeepsEachControlInExactlyOneSection() {
        let layout = PlayerControlLayout.restored(
            from: "",
            legacyOrder: "loop,mute,fullscreen,speed,audioOnly,autoplay",
            legacyHidden: "mute"
        )
        let controls = layout.onPlayer + layout.moreMenu + layout.hidden
        XCTAssertEqual(Set(controls), Set(PlayerTopControl.allCases))
        XCTAssertEqual(controls.count, PlayerTopControl.allCases.count)
        XCTAssertEqual(layout.hidden, [.mute])
        XCTAssertTrue(layout.moreMenu.contains(.quality))
        XCTAssertTrue(layout.moreMenu.contains(.sleepTimer))
        XCTAssertEqual(layout.onPlayer, [.loop, .fullscreen, .speed, .audioOnly, .autoplay])
    }

    func testPlayerControlLayoutMovesAndRoundTrips() {
        var layout = PlayerControlLayout.standard
        layout.move(.quality, to: .onPlayer, before: .fullscreen)
        layout.move(.audioOnly, to: .hidden)
        let restored = PlayerControlLayout.restored(
            from: layout.encoded,
            legacyOrder: "",
            legacyHidden: ""
        )
        XCTAssertEqual(restored, layout)
        XCTAssertEqual(restored.onPlayer, [.quality, .fullscreen, .speed])
        XCTAssertEqual(restored.hidden, [.audioOnly])
    }

    func testMoreThanFourPlayerControlsStayOnPlayerAndRoundTrip() {
        var layout = PlayerControlLayout.standard
        layout.move(.loop, to: .onPlayer)
        layout.move(.quality, to: .onPlayer)
        XCTAssertEqual(layout.onPlayer, [.audioOnly, .fullscreen, .speed, .loop, .quality])
        layout.move(.captions, to: .onPlayer)
        XCTAssertEqual(layout.onPlayer, [.audioOnly, .fullscreen, .speed, .loop, .quality, .captions])
        XCTAssertEqual(
            PlayerControlLayout.restored(from: layout.encoded, legacyOrder: "", legacyHidden: ""),
            layout
        )
    }

    func testPlayerControlsMoveAcrossSectionsAndPersist() {
        var layout = PlayerControlLayout.standard
        layout.move(.audioOnly, to: .onPlayer)
        XCTAssertEqual(layout.onPlayer, [.fullscreen, .speed, .audioOnly])
        layout.move(.mute, to: .hidden)
        XCTAssertEqual(layout.hidden, [.mute])
        layout.move(.mute, to: .moreMenu, before: .quality)
        XCTAssertEqual(layout.moreMenu.first, .mute)
        XCTAssertEqual(PlayerControlLayout.restored(from: layout.encoded, legacyOrder: "", legacyHidden: ""), layout)
    }

    func testNativeListReordersOnlyItsOwnSection() {
        var layout = PlayerControlLayout.standard
        let originalMore = layout.moreMenu

        layout.reorder(in: .onPlayer, fromOffsets: IndexSet(integer: 0), toOffset: 3)

        XCTAssertEqual(layout.onPlayer, [.fullscreen, .speed, .audioOnly])
        XCTAssertEqual(layout.moreMenu, originalMore)
        XCTAssertEqual(layout.hidden, [])
        XCTAssertEqual(
            PlayerControlLayout.restored(from: layout.encoded, legacyOrder: "", legacyHidden: ""),
            layout
        )
    }

    func testInvalidReorderDoesNotChangeLayout() {
        var layout = PlayerControlLayout.standard
        let original = layout

        layout.reorder(in: .onPlayer, fromOffsets: IndexSet(integer: 99), toOffset: 0)

        XCTAssertEqual(layout, original)
    }

    func testPlaylistCountsAcceptDisplayStrings() {
        XCTAssertEqual(Mappers.parseAbbreviatedCount("123 videos"), 123)
        XCTAssertEqual(Mappers.parseAbbreviatedCount("1,234 videos"), 1_234)
        XCTAssertEqual(Mappers.parseAbbreviatedCount("1.2K videos"), 1_200)
        XCTAssertNil(Mappers.parseAbbreviatedCount(nil))
        XCTAssertNil(Mappers.parseAbbreviatedCount(""))
    }

    func testMatchingAspectRatioNeedsNoFillZoom() {
        XCTAssertEqual(PlayerZoomGeometry.fillScale(
            video: CGSize(width: 1920, height: 1080),
            viewport: CGSize(width: 1600, height: 900)
        ), 1, accuracy: 0.0001)
    }

    func testFillZoomHandlesBothLetterboxDirections() {
        let video = CGSize(width: 1920, height: 1080)
        let wide = PlayerZoomGeometry.fillScale(video: video, viewport: CGSize(width: 2400, height: 1080))
        let tall = PlayerZoomGeometry.fillScale(video: video, viewport: CGSize(width: 1920, height: 1350))
        XCTAssertEqual(wide, 1.25, accuracy: 0.0001)
        XCTAssertEqual(tall, 1.25, accuracy: 0.0001)
    }

    func testUnknownVideoSizeIsSafe() {
        XCTAssertEqual(PlayerZoomGeometry.fillScale(video: .zero, viewport: CGSize(width: 800, height: 400)), 1)
        XCTAssertEqual(PlayerZoomGeometry.clamped(.infinity, fillScale: 1.25), 1)
    }

    func testZoomSettlesNearDetentsAndRetainsIntermediatePositions() {
        XCTAssertEqual(PlayerZoomGeometry.settled(1.04, fillScale: 1.4), 1)
        XCTAssertEqual(PlayerZoomGeometry.settled(1.38, fillScale: 1.4), 1.4)
        XCTAssertEqual(PlayerZoomGeometry.settled(1.2, fillScale: 1.4), 1.2)
        XCTAssertEqual(PlayerZoomGeometry.clamped(0.6, fillScale: 1.4), 1)
        XCTAssertEqual(PlayerZoomGeometry.clamped(8, fillScale: 1.4), 3)
    }

    func testScreenFillHasAnAccessibleSnapRangeAndCanBeExceeded() {
        XCTAssertEqual(PlayerZoomGeometry.settled(1.3, fillScale: 1.4), 1.4)
        XCTAssertEqual(PlayerZoomGeometry.settled(1.8, fillScale: 1.4), 1.8)
        XCTAssertEqual(PlayerZoomGeometry.clamped(6, fillScale: 4), 6)
    }

    func testPanningBoundsUseThePictureRatherThanLetterbox() {
        let video = CGSize(width: 1600, height: 900)
        let viewport = CGSize(width: 1000, height: 500)
        XCTAssertEqual(PlayerZoomGeometry.offset(
            CGSize(width: 300, height: 300), scale: 1, video: video, viewport: viewport
        ), .zero)
        let panned = PlayerZoomGeometry.offset(
            CGSize(width: 2000, height: -2000), scale: 2, video: video, viewport: viewport
        )
        XCTAssertEqual(panned.width, 388.8889, accuracy: 0.001)
        XCTAssertEqual(panned.height, -250, accuracy: 0.001)
    }

    func testOffCentrePinchAndTwoFingerPanPreserveArbitraryZoom() {
        let model = PlayerZoomModel()
        model.configure(video: CGSize(width: 2000, height: 1000), viewport: CGSize(width: 1000, height: 500), reduceMotion: true)
        model.pinch(1, focalPoint: CGPoint(x: 200, y: 0), state: .began)
        model.pinch(2, focalPoint: .zero, state: .changed)
        model.pinch(2, focalPoint: .zero, state: .ended)
        XCTAssertEqual(model.scale, 2)
        XCTAssertEqual(model.offset.width, -200)
        XCTAssertFalse(model.isInteracting)

        model.pan(.zero, state: .began)
        model.pan(CGSize(width: 900, height: 50), state: .changed)
        model.pan(CGSize(width: 900, height: 50), state: .ended)
        XCTAssertEqual(model.scale, 2)
        XCTAssertEqual(model.offset.width, 500)
        XCTAssertEqual(model.offset.height, 50)
    }

    func testSimultaneousPinchAndPanSettleOnlyWhenBothFinish() {
        let model = PlayerZoomModel()
        model.configure(video: CGSize(width: 1600, height: 900), viewport: CGSize(width: 2400, height: 900), reduceMotion: true)
        model.pinch(1, focalPoint: .zero, state: .began)
        model.pan(.zero, state: .began)
        model.pinch(1.45, focalPoint: .zero, state: .changed)
        model.pinch(1.45, focalPoint: .zero, state: .ended)
        XCTAssertTrue(model.isInteracting)
        XCTAssertEqual(model.scale, 1.45)
        model.pan(.zero, state: .ended)
        XCTAssertFalse(model.isInteracting)
        XCTAssertEqual(model.scale, 1.5)
        XCTAssertEqual(model.offset, .zero)
        model.reset()
        XCTAssertEqual(model.scale, 1)
    }

    func testPinchingAfterPanKeepsTheFocalPointStationary() {
        let model = PlayerZoomModel()
        model.configure(video: CGSize(width: 2000, height: 1000), viewport: CGSize(width: 1000, height: 500), reduceMotion: true)
        model.pinch(1, focalPoint: .zero, state: .began)
        model.pinch(2, focalPoint: .zero, state: .changed)
        model.pinch(2, focalPoint: .zero, state: .ended)
        model.pan(.zero, state: .began)
        model.pan(CGSize(width: 100, height: 0), state: .changed)
        model.pinch(1, focalPoint: CGPoint(x: 200, y: 0), state: .began)
        model.pinch(1.5, focalPoint: .zero, state: .changed)
        XCTAssertEqual(model.scale, 3)
        XCTAssertEqual(model.offset.width, 0, accuracy: 0.001)
        model.pinch(1.5, focalPoint: .zero, state: .ended)
        model.pan(CGSize(width: 100, height: 0), state: .ended)
        XCTAssertFalse(model.isInteracting)
    }
}
