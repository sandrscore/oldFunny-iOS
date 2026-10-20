import XCTest
@testable import OldFunnyCore

final class VideoPlaybackTests: XCTestCase {
    func testDownvoteEligibilityMatchesAndroidGalleryOverrides() {
        XCTAssertTrue(ViewerInteraction.allowsUnsmile(source: "coll"))
        XCTAssertTrue(ViewerInteraction.allowsUnsmile(source: "tags"))
        for source in ["feat", "subs", "prof", "", "unknown"] { XCTAssertFalse(ViewerInteraction.allowsUnsmile(source: source)) }
    }
    func testLoopOrUnmuteRestartUsesSeekQueueAndCannotOverrideManualPause() throws {
        var state = VideoSeekState()
        XCTAssertTrue(state.restart(current: true, ready: true, manuallyPaused: true).isEmpty)
        XCTAssertTrue(state.restart(current: false, ready: true, manuallyPaused: false).isEmpty)
        let commands = state.restart(current: true, ready: true, manuallyPaused: false)
        let seek = try XCTUnwrap(state.inFlight)
        XCTAssertEqual(commands, [.pause, .seek(seek)]); XCTAssertEqual(seek.milliseconds, 0)
        XCTAssertTrue(state.restart(current: true, ready: true, manuallyPaused: false).isEmpty)
        XCTAssertEqual(state.completed(seek.id, finished: true, current: true, ready: true, manuallyPaused: false), [.play])
    }
    func testCutoffTargetAndTimeMatchAndroidIncludingRightEdge() {
        XCTAssertFalse(VideoSeekState.hasScrubber(duration: 10_000))
        XCTAssertTrue(VideoSeekState.hasScrubber(duration: 10_001))
        XCTAssertEqual(VideoSeekState.target(fraction: 1, duration: 12_437), 12_436)
        XCTAssertEqual(VideoSeekState.target(fraction: 0.5, duration: 12_437), 6_218)
        XCTAssertEqual(VideoSeekState.target(fraction: -3, duration: 12_437), 0)
        XCTAssertEqual(VideoSeekState.target(fraction: .nan, duration: 12_437), 0)
        XCTAssertEqual(VideoSeekState.timestamp(12_999), "00:12")
        XCTAssertEqual(VideoSeekState.timestamp(3_723_000), "62:03")
    }
    func testCoalescingWaitsForFinalSeekAndPreservesPlayIntent() throws {
        var state = VideoSeekState()
        let start = state.begin(fraction: 0.1, duration: 12_000, playing: true, manuallyPaused: false, current: true, ready: true)
        XCTAssertEqual(start.first, .pause)
        let first = try XCTUnwrap(state.inFlight); XCTAssertEqual(first.milliseconds, 1_200)
        XCTAssertTrue(state.request(fraction: 0.3, duration: 12_000, current: true, ready: true).isEmpty)
        XCTAssertTrue(state.request(fraction: 0.75, duration: 12_000, current: true, ready: true).isEmpty)
        XCTAssertTrue(state.release(current: true, ready: true, manuallyPaused: false).isEmpty)
        let commands = state.completed(first.id, finished: true, current: true, ready: true, manuallyPaused: false)
        let last = try XCTUnwrap(state.inFlight)
        XCTAssertEqual(last.milliseconds, 9_000); XCTAssertEqual(commands, [.seek(last)])
        XCTAssertEqual(state.completed(last.id, finished: true, current: true, ready: true, manuallyPaused: false), [.play])
        XCTAssertFalse(state.blocksStart)
    }
    func testPausedSeekAndLateInactiveCompletionCannotStartPlayback() throws {
        var paused = VideoSeekState()
        _ = paused.begin(fraction: 0.5, duration: 12_000, playing: false, manuallyPaused: true, current: true, ready: true)
        let request = try XCTUnwrap(paused.inFlight)
        _ = paused.release(current: true, ready: true, manuallyPaused: true)
        XCTAssertTrue(paused.completed(request.id, finished: true, current: true, ready: true, manuallyPaused: true).isEmpty)
        var moving = VideoSeekState()
        _ = moving.begin(fraction: 0.5, duration: 12_000, playing: true, manuallyPaused: false, current: true, ready: true)
        let old = try XCTUnwrap(moving.inFlight); moving.suspend()
        XCTAssertTrue(moving.completed(old.id, finished: true, current: false, ready: true, manuallyPaused: false).isEmpty)
        moving.reset()
        _ = moving.begin(fraction: 0.8, duration: 12_000, playing: true, manuallyPaused: false, current: true, ready: true)
        let next = try XCTUnwrap(moving.inFlight)
        XCTAssertNotEqual(next.id, old.id)
        XCTAssertTrue(moving.completed(old.id, finished: true, current: true, ready: true, manuallyPaused: false).isEmpty)
        XCTAssertEqual(moving.inFlight, next)
    }
}
