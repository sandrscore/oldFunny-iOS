import XCTest
@testable import OldFunnyCore

final class GIFTimelineTests: XCTestCase {
    func testUnevenDelaysAndExactBoundariesAndLoop() throws {
        let timeline = try GIFTimeline(delays: [0.1, 0.9, 0.2])
        XCTAssertEqual(timeline.frame(at: 0.099), 0); XCTAssertEqual(timeline.frame(at: 0.1), 1)
        XCTAssertEqual(timeline.frame(at: 0.9), 1); XCTAssertEqual(timeline.frame(at: 1), 2)
        XCTAssertEqual(timeline.frame(at: 1.2), 0); XCTAssertEqual(timeline.frame(at: 1200.05), 0)
        XCTAssertEqual(timeline.frame(at: .nan), 0); XCTAssertFalse(timeline.finished(at: 1000))
    }
    func testLongAnimationIsNotReplacedWithStillAndFinitePlaysStopOnLastFrame() throws {
        let timeline = try GIFTimeline(delays: Array(repeating: 0.01, count: 1000), plays: 2)
        XCTAssertEqual(timeline.ends.count, 1000); XCTAssertEqual(timeline.duration, 20, accuracy: 0.00001)
        XCTAssertEqual(timeline.frame(at: 8.005), 400)
        XCTAssertEqual(timeline.frame(at: 40.01), 999); XCTAssertTrue(timeline.finished(at: 40.01))
        XCTAssertFalse(timeline.finished(at: 39.99))
    }
    func testInvalidDelaysAndFrameCountBoundsFailExplicitly() throws {
        let timeline = try GIFTimeline(delays: [0, -1, .nan, .infinity, 0.01])
        XCTAssertEqual(timeline.duration, 0.42, accuracy: 0.00001)
        XCTAssertThrowsError(try GIFTimeline(delays: [])); XCTAssertThrowsError(try GIFTimeline(delays: [1], plays: 0))
        XCTAssertThrowsError(try GIFTimeline(delays: Array(repeating: 0.1, count: 10001)))
    }
    func testPauseAndResumeRetainPhaseAcrossInactiveTime() {
        var clock = GIFClock(); clock.resume(at: 100); clock.resume(at: 101)
        XCTAssertEqual(clock.elapsed(at: 101), 1)
        clock.pause(at: 101.5); clock.pause(at: 200)
        XCTAssertEqual(clock.elapsed(at: 300), 1.5); XCTAssertFalse(clock.running)
        clock.resume(at: 300); XCTAssertEqual(clock.elapsed(at: 300.25), 1.75)
        XCTAssertEqual(clock.elapsed(at: 299), 1.5)
    }
}
