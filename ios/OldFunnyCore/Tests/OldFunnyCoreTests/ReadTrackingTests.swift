import XCTest
@testable import OldFunnyCore

final class ReadTrackingTests: XCTestCase {
    func testOnlySubscriptionsQualifiesDuringMediaLoadingAndAllVisibilityGatesApply() {
        var visible = ReadVisibility(settled: true, foreground: true, windowVisible: true, mediaPanel: true, drawerOpen: false, advertisement: false, rendered: false)
        XCTAssertTrue(visible.qualifies(for: .subscriptions)); XCTAssertFalse(visible.qualifies(for: .featured)); XCTAssertFalse(visible.qualifies(for: .collective))
        visible.rendered = true; XCTAssertTrue(visible.qualifies(for: .featured))
        for key in [\ReadVisibility.settled, \.foreground, \.windowVisible, \.mediaPanel] {
            var hidden = visible; hidden[keyPath: key] = false
            XCTAssertFalse(hidden.qualifies(for: .featured)); XCTAssertFalse(hidden.qualifies(for: .subscriptions))
        }
        for key in [\ReadVisibility.drawerOpen, \.advertisement] {
            var hidden = visible; hidden[keyPath: key] = true
            XCTAssertFalse(hidden.qualifies(for: .featured)); XCTAssertFalse(hidden.qualifies(for: .subscriptions))
        }
    }
    func testFeaturedContinuousExposureResetsForPanelsAccountPostAndClock() {
        var exposure = FeaturedReadExposure()
        XCTAssertFalse(exposure.sample(postID: "Post", scope: "AccountA", now: 100, visible: true))
        XCTAssertFalse(exposure.sample(postID: "Post", scope: "AccountA", now: 1899, visible: true))
        XCTAssertTrue(exposure.sample(postID: "Post", scope: "AccountA", now: 1900, visible: true))
        XCTAssertFalse(exposure.sample(postID: "Post", scope: "AccountA", now: 4000, visible: true))
        XCTAssertFalse(exposure.sample(postID: "Post", scope: "AccountA", now: 4100, visible: false))
        XCTAssertFalse(exposure.sample(postID: "Post", scope: "AccountA", now: 4200, visible: true))
        XCTAssertTrue(exposure.sample(postID: "Post", scope: "AccountA", now: 6000, visible: true))
        XCTAssertFalse(exposure.sample(postID: "Post", scope: "AccountB", now: 6001, visible: true))
        XCTAssertFalse(exposure.sample(postID: "Other", scope: "AccountB", now: 7801, visible: true))
        XCTAssertFalse(exposure.sample(postID: "Other", scope: "AccountB", now: 7000, visible: true))
        XCTAssertTrue(exposure.sample(postID: "Other", scope: "AccountB", now: 8800, visible: true))
        XCTAssertFalse(exposure.sample(postID: "Other", scope: nil, now: 10000, visible: true))
        XCTAssertFalse(exposure.sample(postID: "bad/id", scope: "AccountB", now: 12000, visible: true))
    }
    func testLedgerRestoresPendingAsSeenPreservesFIFOAndAcknowledgesOnlyPending() {
        var ledger = ReadLedger(savedSeen: "Old,Same,Old,bad/id", savedPending: "Same,Pending,Pending")
        XCTAssertEqual(ledger.seen, ["Old", "Same", "Pending"]); XCTAssertEqual(ledger.batch, ["Same", "Pending"])
        XCTAssertFalse(ledger.viewed("Pending")); XCTAssertTrue(ledger.viewed("New")); XCTAssertFalse(ledger.viewed("New"))
        ledger.acknowledged(["Same", "NotPending"])
        XCTAssertEqual(ledger.pending, ["Pending", "New"]); XCTAssertEqual(ledger.seen, ["Old", "Same", "Pending", "New"])
        XCTAssertEqual(ReadLedger(savedSeen: ledger.savedSeen, savedPending: ledger.savedPending), ledger)
        XCTAssertEqual(ReadLedger().pending, [], "Another account starts independently; no global history")
    }
    func testLedgerBoundsHistoryAndPendingAndNeverReordersViewedIDs() {
        var ledger = ReadLedger()
        for i in 0..<2050 { XCTAssertTrue(ledger.viewed("Post\(i)")) }
        XCTAssertEqual(ledger.seen.count, 2048); XCTAssertEqual(ledger.pending.count, 2048)
        XCTAssertEqual(ledger.seen.first, "Post2"); XCTAssertEqual(ledger.batch.count, 30); XCTAssertEqual(ledger.batch.last, "Post31")
        XCTAssertFalse(ledger.viewed("Post2")); XCTAssertEqual(ledger.seen.first, "Post2")
        XCTAssertTrue(ReadLedger.validID(String(repeating: "a", count: 80))); XCTAssertFalse(ReadLedger.validID(String(repeating: "a", count: 81)))
        XCTAssertFalse(ledger.viewed("bad,id")); XCTAssertFalse(ledger.viewed(""))
        XCTAssertTrue(ReadLedger(savedSeen: String(repeating: "a", count: 2048 * 81 + 1)).seen.isEmpty)
    }
    func testSubscriptionStaleCounterDropsNewArrivalsAndRestartRetireCreditsOnce() throws {
        var progress = SubscriptionUnreadProgress()
        XCTAssertNil(progress.remaining); XCTAssertEqual(try progress.merge(server: 12), 12)
        for _ in 0..<3 { progress.viewed() }; XCTAssertEqual(progress.remaining, 9)
        XCTAssertEqual(try progress.merge(server: 12), 9)
        XCTAssertEqual(try progress.merge(server: 10), 9); XCTAssertEqual(progress.credit, 1)
        XCTAssertEqual(try progress.merge(server: 14), 13)
        progress = SubscriptionUnreadProgress(saved: progress.saved)
        XCTAssertEqual(try progress.merge(server: 14), 13); progress.viewed(); XCTAssertEqual(progress.remaining, 12)
        XCTAssertEqual(try progress.merge(server: 0), 0); progress.viewed(); XCTAssertEqual(progress.credit, 0)
        XCTAssertThrowsError(try progress.merge(server: -1))
        XCTAssertThrowsError(try progress.merge(server: Int(Int32.max) + 1))
    }
    func testUnknownCounterAndExplicitClearPersistenceNeverConfuseNavigationWithSuccess() throws {
        var progress = SubscriptionUnreadProgress()
        for _ in 0..<3 { progress.viewed() }; XCTAssertNil(progress.remaining)
        progress = SubscriptionUnreadProgress(saved: progress.saved); XCTAssertEqual(progress.credit, 3)
        XCTAssertEqual(try progress.merge(server: 2), 0)
        XCTAssertEqual(try progress.merge(server: 5), 3)
        let navigationSnapshot = SubscriptionUnreadProgress(saved: progress.saved)
        XCTAssertEqual(navigationSnapshot.remaining, 3, "Ordinary navigation retains progress")
        progress.clearConfirmed(); XCTAssertEqual(progress.remaining, 0); XCTAssertEqual(try progress.merge(server: 5), 0)
        for invalid in ["", "1", "1,2,3", "-2,0", "1,-1", "1,2", "2147483648,0", "0,2147483648", "x,0"] {
            let reset = SubscriptionUnreadProgress(saved: invalid); XCTAssertNil(reset.remaining); XCTAssertEqual(reset.credit, 0)
        }
    }
}
