import XCTest

final class ViewerTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    private func capture(_ name: String, app: XCUIApplication) {
        let picture = XCTAttachment(screenshot: app.screenshot()); picture.name = name; picture.lifetime = .keepAlways; add(picture)
    }
    private func waitUntil(_ message: String, timeout: TimeInterval = 8, _ condition: @escaping () -> Bool) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed, message)
    }
    private func videoTime(_ scrubber: XCUIElement) -> (position: Int, duration: Int, idle: Bool) {
        let text = scrubber.value as? String ?? ""
        let fields = text.components(separatedBy: ";")[0].components(separatedBy: "/")
        return (Int(fields.first ?? "") ?? -1, fields.count > 1 ? Int(fields[1]) ?? -1 : -1, text.contains("; idle;"))
    }
    private func openOfflineProfile(_ app: XCUIApplication, writes: Bool = false) {
        app.launchArguments = ["--ui-tests", "--ui-tests-account", "--ui-tests-profile"] + (writes ? ["--ui-tests-profile-writes"] : [])
        app.launch(); XCTAssertTrue(app.buttons["Open menu"].waitForExistence(timeout: 10))
        app.buttons["Open menu"].tap(); app.buttons["Profile"].tap()
        XCTAssertTrue(app.collectionViews.cells["grid-post-GridPost0"].waitForExistence(timeout: 10))
    }
    func testProfileGridViewerRetainsScrollAndFeaturedUsesSeparateSource() {
        let app = XCUIApplication(); openOfflineProfile(app)
        let collection = app.collectionViews["profile-grid"], tile = collection.cells["grid-post-GridPost20"]
        for _ in 0..<4 { if tile.isHittable { break }; collection.swipeUp() }
        XCTAssertTrue(tile.isHittable); let before = tile.frame.minY; tile.tap()
        XCTAssertTrue(app.buttons["21 smiles, smile"].waitForExistence(timeout: 5)); app.swipeLeft(velocity: .fast)
        XCTAssertTrue(app.buttons["22 smiles, smile"].waitForExistence(timeout: 5)); app.buttons["Back"].tap()
        XCTAssertTrue(tile.waitForExistence(timeout: 5)); XCTAssertEqual(tile.frame.minY, before, accuracy: 3)
        app.buttons["Profile information"].tap(); app.buttons["5 featured"].tap()
        XCTAssertTrue(app.otherElements["profile-featured-grid"].waitForExistence(timeout: 5))
        XCTAssertEqual(collection.cells.count, 5)
        collection.cells["grid-post-GridPost10"].tap(); XCTAssertTrue(app.buttons["11 smiles, smile"].waitForExistence(timeout: 5))
        app.swipeLeft(velocity: .fast); XCTAssertTrue(app.buttons["21 smiles, smile"].waitForExistence(timeout: 5))
        app.buttons["Back"].tap(); XCTAssertEqual(collection.cells.count, 5)
        app.buttons["Back"].tap(); XCTAssertTrue(app.buttons["5 featured"].waitForExistence(timeout: 5))
        capture("profile-information-and-featured-return", app: app)
    }
    func testProfileSearchCombinesTagsOriginalAuthorAndRepubToggle() {
        let app = XCUIApplication(); openOfflineProfile(app)
        app.buttons["Advanced Search"].tap()
        let tags = app.textFields["profile-tags"]; XCTAssertTrue(tags.waitForExistence(timeout: 5)); tags.tap(); tags.typeText("dogs\n")
        app.buttons["profile-media-filter"].tap(); app.buttons["Images"].tap()
        app.buttons["profile-author-filter"].tap()
        let search = app.textFields["user-search"]; XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeText("Writer")
        let writer = app.tables.cells["user-row-Writer"]; XCTAssertTrue(writer.waitForExistence(timeout: 5)); writer.tap()
        let collection = app.collectionViews["profile-grid"]
        waitUntil("The profile search must find all four source-backed Writer posts") { collection.cells.count == 4 }
        XCTAssertTrue(collection.cells["grid-post-GridPost5"].exists)
        app.buttons["Include republished posts"].tap()
        XCTAssertTrue(app.staticTexts["No matching posts."].waitForExistence(timeout: 5)); XCTAssertFalse(app.buttons["profile-author-filter"].isEnabled)
        app.buttons["Include republished posts"].tap()
        waitUntil("Author selection and matches must return with repubs") { collection.cells.count == 4 }
        app.buttons["Search options"].tap(); app.buttons["Clear filters"].tap()
        waitUntil("Clearing filters reuses already-scanned timeline pages") { collection.cells.count == 44 }
        capture("profile-search-restored-results", app: app)
    }
    func testOwnProfilePinReadbackAndGridBadge() {
        let app = XCUIApplication(); openOfflineProfile(app, writes: true)
        let tile = app.collectionViews.cells["grid-post-GridPost0"]; tile.tap()
        let media = app.otherElements["post-media"]; XCTAssertTrue(app.buttons["1 smiles, smile"].waitForExistence(timeout: 5))
        media.press(forDuration: 1); app.buttons["Pin"].tap()
        media.press(forDuration: 1); XCTAssertTrue(app.buttons["Pinned"].waitForExistence(timeout: 5)); app.buttons["Cancel"].tap()
        app.buttons["Back"].tap()
        waitUntil("Only confirmed pin readback updates the grid badge") { tile.value as? String == "Pinned" }
        capture("profile-confirmed-pin-badge", app: app)
        tile.tap(); media.press(forDuration: 1); app.buttons["Pinned"].tap(); app.buttons["Back"].tap()
        waitUntil("Unpin readback removes the badge") { tile.exists && tile.value as? String != "Pinned" }
    }
    func testProfileSubscriberListAndConfirmedSubscribeToggle() {
        let app = XCUIApplication(); openOfflineProfile(app, writes: true)
        app.buttons["Profile information"].tap(); app.buttons["2 subscribers"].tap()
        let user = app.tables.cells["user-row-Reader1"]; XCTAssertTrue(user.waitForExistence(timeout: 5)); user.tap()
        let subscribe = app.buttons["Subscribe"]; XCTAssertTrue(subscribe.waitForExistence(timeout: 5)); subscribe.tap()
        XCTAssertTrue(app.buttons["Subscribed"].waitForExistence(timeout: 5)); app.buttons["Subscribed"].tap()
        XCTAssertTrue(subscribe.waitForExistence(timeout: 5))
        capture("other-profile-subscribe-confirmed", app: app)
    }
    func testVideoPausedSeekMuteZoomAndPageReturnUseActualPlayer() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-tests", "--ui-tests-video"]; app.launch()
        let video = app.descendants(matching: .any)["post-video"].firstMatch
        let bar = app.descendants(matching: .any)["video-scrubber"].firstMatch
        XCTAssertTrue(video.waitForExistence(timeout: 10)); XCTAssertTrue(bar.waitForExistence(timeout: 10))
        waitUntil("Actual player must advance") { self.videoTime(bar).position > 500 }
        XCTAssertEqual(video.value as? String, "Playing")
        XCTAssertEqual(videoTime(bar).duration, 12400, accuracy: 150)
        video.tap(); waitUntil("Single confirmed tap pauses video") { video.value as? String == "Paused" }
        let target = Int(Double(videoTime(bar).duration) * 0.78)
        bar.coordinate(withNormalizedOffset: CGVector(dx: 0.78, dy: 0.8)).tap()
        waitUntil("Accurate seek must land between sparse keyframes while paused") {
            let time = self.videoTime(bar); return time.idle && abs(time.position - target) < 150
        }
        waitUntil("A decoded frame, not just the playback clock, must reach the sparse-keyframe seek target") {
            let value = bar.value as? String ?? ""
            let suffix = value.components(separatedBy: "frame=").last ?? ""
            let frame = Int(suffix.components(separatedBy: ";").first ?? "") ?? -1
            return abs(frame - target) < 150 && value.contains("visible=true")
        }
        XCTAssertEqual(video.value as? String, "Paused")
        let paused = videoTime(bar).position
        let sound = app.buttons["Unmute video"]
        XCTAssertTrue(sound.waitForExistence(timeout: 5)); sound.tap()
        XCTAssertTrue(app.buttons["Mute video"].exists)
        XCTAssertEqual(videoTime(bar).position, paused, accuracy: 150, "Unmuting a paused clip must not restart it")
        let media = app.otherElements["post-media"]
        // The actual video viewport is shorter than the entire post scene;
        // root-scene pinch endpoints can land outside this scroll view.
        let zoom = app.scrollViews["post-media-zoom"]
        XCTAssertTrue(zoom.exists); zoom.pinch(withScale: 2, velocity: 2)
        XCTAssertFalse(app.buttons["Mute video"].exists)
        XCTAssertEqual(video.value as? String, "Paused")
        capture("paused-video-zoomed-mark", app: app)
        // XCTest pinch scale is approximate; deliberately clamp to the fitted
        // minimum instead of assuming two generated gestures are exact inverses.
        zoom.pinch(withScale: 0.1, velocity: -4)
        XCTAssertTrue(app.buttons["Mute video"].waitForExistence(timeout: 5), "Zoom trace: \(String(describing: media.value))")
        app.buttons["3 comments"].tap(); XCTAssertTrue(app.textFields["comment-draft"].waitForExistence(timeout: 5))
        app.buttons["Back"].tap(); XCTAssertTrue(video.waitForExistence(timeout: 5))
        XCTAssertEqual(video.value as? String, "Paused")
        app.swipeLeft(velocity: .fast)
        XCTAssertTrue(app.buttons["NextFan, Featured, open profile"].waitForExistence(timeout: 5))
        app.swipeRight(velocity: .fast); XCTAssertTrue(video.waitForExistence(timeout: 5))
        XCTAssertEqual(video.value as? String, "Paused")
        XCTAssertEqual(videoTime(bar).position, paused, accuracy: 150)
        capture("paused-video-seek-retained-after-page", app: app)
        video.tap(); waitUntil("Returning to a paused page must require explicit play") { self.videoTime(bar).position > paused + 300 }
        app.buttons["Mute video"].tap(); app.buttons["Unmute video"].tap()
        waitUntil("Enabling sound during playback restarts from zero") { self.videoTime(bar).position < 3000 }
        XCTAssertEqual(video.value as? String, "Playing")
    }
    func testUnsmileContextAndTripleTapClassification() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-tests", "--ui-tests-account", "--ui-tests-reactions"]; app.launch()
        let media = app.otherElements["post-media"]
        XCTAssertTrue(app.buttons["128 smiles, smile"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Unsmile"].exists)
        app.buttons["Open menu"].tap(); app.buttons["Collective"].tap()
        XCTAssertTrue(app.buttons["Unsmile"].waitForExistence(timeout: 5))
        media.tap(withNumberOfTaps: 3, numberOfTouches: 1)
        waitUntil("Triple tap must send only one unsmile and no intermediate smile") { media.value as? String == "unsmiles" }
        XCTAssertTrue(app.buttons["128 smiles, smile"].exists)
        media.doubleTap()
        waitUntil("A later double tap must send exactly one smile") { media.value as? String == "unsmiles,smiles" }
        XCTAssertTrue(app.buttons["129 smiles, remove smile"].exists)
    }
    func testConfirmedReplyAndRootDeletionUpdatePostCountWithoutChangingReplyCountTwice() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-tests", "--ui-tests-account", "--ui-tests-accepted-comments"]; app.launch()
        XCTAssertTrue(app.buttons["5 comments"].waitForExistence(timeout: 10)); app.buttons["5 comments"].tap()
        let replies = app.staticTexts["2 replies"].firstMatch
        XCTAssertTrue(replies.waitForExistence(timeout: 5)); replies.tap()
        let root = app.staticTexts["The classic look is coming back."]
        XCTAssertTrue(root.waitForExistence(timeout: 5))
        let draft = app.textFields["comment-draft"]; draft.tap(); draft.typeText("Confirmed offline reply")
        app.buttons["Send comment"].tap()
        XCTAssertTrue(app.staticTexts["Confirmed offline reply"].waitForExistence(timeout: 5))
        app.buttons["Refresh"].tap()
        XCTAssertTrue(app.staticTexts["3 replies"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["Back"].tap()
        XCTAssertTrue(app.staticTexts["6 comments"].waitForExistence(timeout: 5))
        app.staticTexts["3 replies"].firstMatch.tap()
        XCTAssertTrue(root.waitForExistence(timeout: 5)); root.press(forDuration: 1)
        app.buttons["Delete"].tap()
        XCTAssertTrue(app.alerts["Delete this comment?"].waitForExistence(timeout: 5)); app.alerts.buttons["Delete"].tap()
        XCTAssertTrue(app.staticTexts["Comment deleted."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["3 replies"].firstMatch.exists)
        capture("root-deleted-replies-retained", app: app)
        app.buttons["Back"].tap()
        XCTAssertTrue(app.staticTexts["5 comments"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["3 replies"].exists)
        app.buttons["Back"].tap()
        XCTAssertTrue(app.buttons["5 comments"].waitForExistence(timeout: 5))
    }
    func testUnconfirmedInlineReactionKeepsThreadAndDraft() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-tests", "--ui-tests-account"]; app.launch()
        XCTAssertTrue(app.buttons["3 comments"].waitForExistence(timeout: 10)); app.buttons["3 comments"].tap()
        let draft = app.textFields["comment-draft"]; XCTAssertTrue(draft.waitForExistence(timeout: 5))
        draft.tap(); draft.typeText("Do not lose this")
        let smile = app.buttons["comment-smile-PreviewComment1"]
        smile.tap() // First outside tap only dismisses the keyboard.
        XCTAssertEqual(app.keyboards.count, 0); XCTAssertFalse(app.alerts.firstMatch.exists)
        smile.tap() // The offline transport rejects social writes.
        XCTAssertTrue(app.alerts["oldFunny"].waitForExistence(timeout: 5)); app.alerts.buttons["OK"].tap()
        XCTAssertEqual(draft.value as? String, "Do not lose this")
        XCTAssertEqual(smile.label, "Smile comment")
        XCTAssertTrue(app.otherElements["comments-screen"].exists)
        capture("unconfirmed-comment-reaction-keeps-draft", app: app)
    }
    func testReplyThreadRetainsRootRecipientAndDraftThroughBack() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-tests", "--ui-tests-account"]; app.launch()
        XCTAssertTrue(app.buttons["3 comments"].waitForExistence(timeout: 10)); app.buttons["3 comments"].tap()
        let replies = app.staticTexts["2 replies"].firstMatch
        XCTAssertTrue(replies.waitForExistence(timeout: 5)); replies.tap()
        let reply = app.staticTexts["Reply number one"]
        XCTAssertTrue(reply.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["The classic look is coming back."].exists)
        reply.tap()
        let draft = app.textFields["comment-draft"]; draft.typeText("Reply draft")
        XCTAssertEqual(app.staticTexts["reply-recipient"].label, "Reply to ReaderOne")
        app.buttons["Back"].tap()
        XCTAssertTrue(replies.waitForExistence(timeout: 5)); replies.tap()
        XCTAssertTrue(reply.waitForExistence(timeout: 5))
        XCTAssertEqual(draft.value as? String, "Reply draft")
        XCTAssertEqual(app.staticTexts["reply-recipient"].label, "Reply to ReaderOne")
        capture("retained-reply-root-recipient-draft", app: app)
        app.buttons["Cancel recipient and clear reply text"].tap()
        XCTAssertFalse(app.staticTexts["reply-recipient"].exists)
        XCTAssertEqual(draft.value as? String, "Say something funny…")
    }
    func testVerticalPanelsRetainPostAndDraftWithoutPushingComments() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-tests"]; app.launch()
        let media = app.otherElements["post-media"]
        XCTAssertTrue(media.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["128 smiles, smile"].waitForExistence(timeout: 5))
        media.swipeUp(velocity: .fast)
        XCTAssertTrue(app.staticTexts["3 comments"].waitForExistence(timeout: 5))
        let draft = app.textFields["comment-draft"]; draft.tap(); draft.typeText("Keep this draft")
        // The first outside tap dismisses editing, rather than opening a reply.
        app.tables.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.03)).tap()
        XCTAssertEqual(app.keyboards.count, 0)
        let comments = app.otherElements["comments-screen"]
        XCTAssertTrue(comments.exists, "The keyboard-dismissal tap must not open the underlying author or reply")
        XCTAssertEqual(draft.value as? String, "Keep this draft")
        let start = comments.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.03))
        let end = comments.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.60))
        // XCTest's nominal 750pt/s coordinate drag ended at 412pt/s on this
        // simulator: correctly below Android's 1500 physical px/s threshold.
        // Verify rejection, then synthesize an actual above-threshold fling.
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0)
        XCTAssertTrue(comments.exists); XCTAssertEqual(draft.value as? String, "Keep this draft")
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: XCUIGestureVelocity(rawValue: 1500), thenHoldForDuration: 0)
        XCTAssertTrue(app.buttons["128 smiles, smile"].waitForExistence(timeout: 5), "Gesture trace: \(String(describing: app.otherElements["post-scene"].firstMatch.value))")
        media.swipeUp(velocity: .fast)
        XCTAssertTrue(draft.waitForExistence(timeout: 5)); XCTAssertEqual(draft.value as? String, "Keep this draft")
        capture("comments-draft-retained", app: app)
        app.buttons["Back"].tap()
        XCTAssertTrue(app.buttons["128 smiles, smile"].waitForExistence(timeout: 5))
        media.swipeDown(velocity: .fast)
        XCTAssertTrue(app.staticTexts["Post information"].waitForExistence(timeout: 5))
        capture("information-panel", app: app)
        app.otherElements["post-information"].swipeUp(velocity: .fast)
        XCTAssertTrue(app.buttons["128 smiles, smile"].waitForExistence(timeout: 5))
        capture("returned-to-post", app: app)
    }
    func testCommentTapAndSwipeShareOnePanelAndDoNotLoseKeyboardDraft() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-tests"]; app.launch()
        XCTAssertTrue(app.buttons["3 comments"].waitForExistence(timeout: 10)); app.buttons["3 comments"].tap()
        let draft = app.textFields["comment-draft"]; XCTAssertTrue(draft.waitForExistence(timeout: 5))
        draft.tap(); draft.typeText("Unsent")
        app.buttons["Back"].tap()
        XCTAssertTrue(app.buttons["128 smiles, smile"].waitForExistence(timeout: 5))
        app.otherElements["post-media"].swipeUp(velocity: .fast)
        XCTAssertTrue(draft.waitForExistence(timeout: 5)); XCTAssertEqual(draft.value as? String, "Unsent")
    }
    func testHorizontalPagingAndZoomTakePriorityOverPanelNavigation() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-tests"]; app.launch()
        let media = app.otherElements["post-media"]
        XCTAssertTrue(app.buttons["ClassicFan, Featured, open profile"].waitForExistence(timeout: 10))
        let picture = app.images["post-image"]
        XCTAssertTrue(picture.waitForExistence(timeout: 5))
        XCTAssertEqual(picture.frame.height / picture.frame.width, 760.0 / 640.0, accuracy: 0.02, "The fitted image must use the resolved media viewport")
        app.swipeLeft(velocity: .fast)
        XCTAssertTrue(app.buttons["NextFan, Featured, open profile"].waitForExistence(timeout: 5))
        app.swipeRight(velocity: .fast)
        XCTAssertTrue(app.buttons["ClassicFan, Featured, open profile"].waitForExistence(timeout: 5))
        media.pinch(withScale: 2, velocity: 2)
        media.swipeUp(velocity: .fast)
        XCTAssertFalse(app.staticTexts["3 comments"].exists)
        XCTAssertTrue(app.buttons["128 smiles, smile"].exists)
        capture("zoom-keeps-media-panel", app: app)
    }
    func testAttachmentPickerBackAndRemovalPreserveDraft() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-tests", "--ui-tests-account"]; app.launch()
        XCTAssertTrue(app.buttons["3 comments"].waitForExistence(timeout: 10)); app.buttons["3 comments"].tap()
        let draft = app.textFields["comment-draft"]; XCTAssertTrue(draft.waitForExistence(timeout: 5))
        draft.tap(); draft.typeText("Keep text and attachment")
        app.buttons["Attach one of your posts"].tap()
        let choice = app.collectionViews.cells.firstMatch
        XCTAssertTrue(choice.waitForExistence(timeout: 5)); choice.tap()
        let remove = app.buttons["remove-comment-attachment"]
        XCTAssertTrue(remove.waitForExistence(timeout: 5)); XCTAssertEqual(draft.value as? String, "Keep text and attachment")
        app.buttons["Attach one of your posts"].tap()
        XCTAssertTrue(choice.waitForExistence(timeout: 5)); app.buttons["Back"].tap()
        XCTAssertTrue(remove.waitForExistence(timeout: 5)); XCTAssertEqual(draft.value as? String, "Keep text and attachment")
        app.buttons["Refresh"].tap()
        XCTAssertTrue(remove.exists); XCTAssertEqual(draft.value as? String, "Keep text and attachment")
        capture("attachment-x-and-retained-draft", app: app)
        remove.tap()
        XCTAssertFalse(remove.exists); XCTAssertEqual(draft.value as? String, "Keep text and attachment")
    }
}
