import XCTest

final class ViewerTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    private func capture(_ name: String, app: XCUIApplication) {
        let picture = XCTAttachment(screenshot: app.screenshot()); picture.name = name; picture.lifetime = .keepAlways; add(picture)
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
