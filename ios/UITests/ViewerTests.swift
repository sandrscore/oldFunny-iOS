import XCTest

final class ViewerTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    private func capture(_ name: String, app: XCUIApplication) {
        let picture = XCTAttachment(screenshot: app.screenshot()); picture.name = name; picture.lifetime = .keepAlways; add(picture)
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
        let start = comments.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.03))
        let end = comments.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.60))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .fast, thenHoldForDuration: 0)
        XCTAssertTrue(app.buttons["128 smiles, smile"].waitForExistence(timeout: 5))
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
}
