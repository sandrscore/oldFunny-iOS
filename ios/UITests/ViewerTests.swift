import XCTest
import UIKit

final class ViewerTests: XCTestCase {
    func testExploreTagPagingViewerBackAndMixedRecentUserSearchUseActualRoutes() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-tests", "--ui-tests-account", "--ui-tests-profile", "--ui-tests-explore"]
        app.launch(); XCTAssertTrue(app.buttons["Open menu"].waitForExistence(timeout: 10)); app.buttons["Open menu"].tap(); app.buttons["Explore"].tap()
        let screen = app.otherElements["explore-screen"], query = app.textFields["explore-query"]
        XCTAssertTrue(screen.waitForExistence(timeout: 5))
        let cats = app.tables.cells["explore-tag-cats"]; XCTAssertTrue(cats.waitForExistence(timeout: 5)); cats.tap()
        let grid = app.collectionViews["tag-grid"]
        XCTAssertTrue(grid.waitForExistence(timeout: 5))
        let retry = app.buttons["Could not load more. Tap to retry."]
        XCTAssertTrue(retry.waitForExistence(timeout: 5)); XCTAssertEqual(grid.value as? String, "12 posts", "A failed continuation retains the first page")
        retry.tap()
        waitUntil("Both server pages must merge without the duplicate TagPost11") { grid.value as? String == "26 posts" }
        let last = grid.cells["grid-post-TagPost25"]
        for _ in 0..<5 { if last.isHittable { break }; grid.swipeUp() }
        XCTAssertTrue(last.isHittable); last.tap()
        XCTAssertTrue(app.otherElements["tag-gallery"].waitForExistence(timeout: 5))
        let smile = app.buttons["26 smiles, smile"]
        XCTAssertTrue(smile.waitForExistence(timeout: 5)); smile.tap()
        XCTAssertTrue(app.buttons["27 smiles, remove smile"].waitForExistence(timeout: 5), "The exact trending:cats source must reach the fixture API")
        XCTAssertTrue(app.buttons["Unsmile"].exists); app.buttons["Unsmile"].tap()
        XCTAssertTrue(app.buttons["26 smiles, smile"].waitForExistence(timeout: 5))
        app.buttons["Back"].tap(); XCTAssertTrue(last.waitForExistence(timeout: 5)); XCTAssertTrue(last.isHittable, "Viewer Back retains the selected grid's scroll")
        app.buttons["Back"].tap(); XCTAssertTrue(query.waitForExistence(timeout: 5))
        query.tap(); query.typeText("r")
        app.segmentedControls["explore-tabs"].buttons["iFunnyers"].tap()
        Thread.sleep(forTimeInterval: 0.4)
        XCTAssertFalse((screen.value as? String ?? "").contains("q=r&"), "One UTF16 character cannot trigger user search")
        query.tap(); query.typeText("e")
        let reader = app.tables.cells["user-row-Reader1"]
        XCTAssertTrue(reader.waitForExistence(timeout: 5))
        XCTAssertTrue(app.tables.cells["user-row-Reader2"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.tables["explore-results"].cells.count, 2, "Repeated Reader1 across pages appears once")
        reader.tap(); XCTAssertTrue(app.otherElements["user-profile"].waitForExistence(timeout: 5))
        app.buttons["Back"].tap(); XCTAssertEqual(query.value as? String, "re"); XCTAssertTrue(reader.exists)
        query.tap(); query.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 2))
        XCTAssertTrue(cats.waitForExistence(timeout: 5)); XCTAssertTrue(reader.exists, "Ordinary Explore keeps tags and users in the same history")
        XCTAssertLessThan(reader.frame.minY, cats.frame.minY, "Most recently selected user is above the earlier tag")
        capture("explore-mixed-recents-and-tag-return", app: app)
        reader.tap(); XCTAssertTrue(app.buttons["Advanced Search"].waitForExistence(timeout: 5))
        app.buttons["Advanced Search"].tap(); app.buttons["profile-author-filter"].tap()
        XCTAssertTrue(app.buttons["Clear recent users"].waitForExistence(timeout: 5)); app.buttons["Clear recent users"].tap()
        app.buttons["Back"].tap(); app.buttons["Back"].tap(); app.buttons["Back"].tap()
        XCTAssertTrue(cats.waitForExistence(timeout: 5)); XCTAssertFalse(reader.exists, "Clearing author-only recents preserves Explore tag history")
        app.buttons["Clear recent searches"].tap()
        XCTAssertTrue(app.staticTexts["No recent searches."].waitForExistence(timeout: 5))
        XCTAssertFalse(cats.exists); XCTAssertFalse(reader.exists)
        query.tap(); query.typeText("ca")
        app.segmentedControls["explore-tabs"].buttons["Tags"].tap()
        let suggestion = app.tables.cells["explore-tag-cat_pictures"]
        XCTAssertTrue(suggestion.waitForExistence(timeout: 5), "Typed tags use the suggestions endpoint")
        app.tables.cells["explore-tag-cats"].tap()
        let first = app.collectionViews["tag-grid"].cells["grid-post-TagPost0"]
        XCTAssertTrue(first.waitForExistence(timeout: 5)); first.tap()
        XCTAssertTrue(app.buttons["1 smiles, smile"].waitForExistence(timeout: 5)); app.buttons["1 smiles, smile"].tap()
        XCTAssertTrue(app.buttons["2 smiles, remove smile"].waitForExistence(timeout: 5), "A typed tag must send tag:cats, not trending:cats")
        capture("explore-typed-tag-source", app: app)
    }
    func testFeaturedReadWaitsForRenderedMediaAndContinuousUnobscuredSelection() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-tests", "--ui-tests-reads", "--ui-tests-read-loading"]
        app.launch()
        let trace = app.staticTexts["offline-read-trace"]
        XCTAssertTrue(trace.waitForExistence(timeout: 10))
        XCTAssertTrue(trace.label.contains("rendered=false"))
        app.buttons["Open menu"].tap()
        waitUntil("The image should eventually decode behind the open drawer", timeout: 12) { trace.label.contains("rendered=true") }
        Thread.sleep(forTimeInterval: 2.2)
        XCTAssertFalse(trace.label.contains("feat:"), "A loaded but obscured post is not a read")
        app.buttons["Featured"].press(forDuration: 0.8)
        XCTAssertFalse(app.alerts["Featured"].exists, "Featured has no mark-all popup")
        if app.buttons["Featured"].exists { app.buttons["Featured"].tap() }
        app.buttons["3 comments"].tap()
        XCTAssertTrue(app.textFields["comment-draft"].waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 2.2)
        XCTAssertFalse(trace.label.contains("feat:"), "Comments cannot accumulate Featured exposure")
        app.buttons["Back"].tap()
        waitUntil("A continuous rendered media interval sends the actual selected ID", timeout: 6) { trace.label.contains("feat:PreviewPost") }
        XCTAssertFalse(trace.label.contains("NextPost"), "A prefetched neighbor is not read")
        let image = app.images["post-image"]; image.swipeLeft()
        waitUntil("Settled next page is independently exposed", timeout: 6) { trace.label.contains("feat:NextPost") }
        capture("featured-read-visible-selection", app: app)
    }
    func testSubscriptionLoadingCreditsBadgeAndOnlyConfirmedExplicitClearRemovesUnread() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-tests", "--ui-tests-account", "--ui-tests-reads", "--ui-tests-read-loading", "--ui-tests-read-clear-failure", "--ui-tests-read-refresh", "--ui-tests-read-clear-delay"]
        app.launch()
        let trace = app.staticTexts["offline-read-trace"]
        XCTAssertTrue(trace.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["3 comments"].waitForExistence(timeout: 10), "Read wrapper must preserve successful automatic token refresh")
        XCTAssertTrue(trace.label.contains("token-refresh"))
        app.buttons["Open menu"].tap(); app.buttons["Subscriptions"].tap()
        waitUntil("Subscriptions credits the selected post before media renders", timeout: 5) { trace.label.contains("subs:PreviewPost") && trace.label.contains("rendered=false") && trace.label.contains("unread=9") }
        app.buttons["Open menu"].tap()
        let subscriptions = app.buttons["Subscriptions"]
        XCTAssertEqual(subscriptions.value as? String, "9 unread")
        subscriptions.press(forDuration: 0.8)
        let options = app.alerts["Subscriptions"]; XCTAssertTrue(options.waitForExistence(timeout: 5))
        options.buttons["Cancel"].tap()
        XCTAssertFalse(trace.label.contains("subs:all")); XCTAssertEqual(subscriptions.value as? String, "9 unread")
        subscriptions.press(forDuration: 0.8); app.alerts["Subscriptions"].buttons["Mark as viewed"].tap()
        let failure = app.alerts["oldFunny"]; XCTAssertTrue(failure.waitForExistence(timeout: 5)); failure.buttons["OK"].tap()
        XCTAssertEqual(subscriptions.value as? String, "9 unread", "Uncertain explicit clear preserves local credit")
        subscriptions.press(forDuration: 0.8); app.alerts["Subscriptions"].buttons["Mark as viewed"].tap()
        waitUntil("Explicit clearing exposes its pending state") { subscriptions.value as? String == "Marking as viewed" }
        subscriptions.press(forDuration: 0.8)
        let pending = app.alerts["Subscriptions"]
        XCTAssertTrue(pending.waitForExistence(timeout: 5)); XCTAssertFalse(pending.buttons["Mark as viewed"].isEnabled)
        pending.buttons["Cancel"].tap()
        waitUntil("Confirmed explicit success clears the badge", timeout: 5) { subscriptions.value as? String == "0 unread" }
        XCTAssertEqual(trace.label.components(separatedBy: "subs:all").count - 1, 2, "One failed choice plus one confirmed choice; no pending duplicate")
        app.buttons["Collective"].tap()
        app.buttons["Open menu"].tap()
        XCTAssertEqual(app.buttons["Subscriptions"].value as? String, "0 unread", "Ordinary section navigation preserves progress")
        capture("subscriptions-confirmed-unread-clear", app: app)
    }
    override func setUpWithError() throws { continueAfterFailure = false }
    private func capture(_ name: String, app: XCUIApplication) {
        let picture = XCTAttachment(screenshot: app.screenshot()); picture.name = name; picture.lifetime = .keepAlways; add(picture)
    }
    private func waitUntil(_ message: String, timeout: TimeInterval = 8, details: (() -> String)? = nil, _ condition: @escaping () -> Bool) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        let result = XCTWaiter.wait(for: [expectation], timeout: timeout)
        XCTAssertEqual(result, .completed, message + (result == .completed ? "" : "\n" + (details?() ?? "")))
    }
    private func videoTime(_ scrubber: XCUIElement) -> (position: Int, duration: Int, idle: Bool) {
        let text = scrubber.value as? String ?? ""
        let fields = text.components(separatedBy: ";")[0].components(separatedBy: "/")
        return (Int(fields.first ?? "") ?? -1, fields.count > 1 ? Int(fields[1]) ?? -1 : -1, text.contains("; idle;"))
    }
    private func gifFields(_ image: XCUIElement) -> [String: String] {
        (image.value as? String ?? "").components(separatedBy: "; ").reduce(into: [:]) { result, field in
            let parts = field.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2 { result[parts[0]] = parts[1] }
        }
    }
    private func chooseMention(_ app: XCUIApplication, prefix: String, defaults: Bool = false) {
        let draft = app.textFields["comment-draft"]; draft.tap(); draft.typeText(prefix + "@")
        if defaults { XCTAssertTrue(app.tables.cells["mention-user-Reader1"].waitForExistence(timeout: 5)) }
        draft.typeText("r")
        XCTAssertTrue(app.buttons["mention-status"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["mention-status"].label, "Type one more character to search")
        draft.typeText("e")
        let choice = app.tables.cells["mention-user-Reader2"]
        XCTAssertTrue(choice.waitForExistence(timeout: 5), "The second paginated result must be reachable")
        XCTAssertEqual(app.tables["mention-suggestions"].cells.count, 2, "Duplicate IDs across pages appear once")
        choice.tap(); XCTAssertEqual(draft.value as? String, prefix + "ReaderTwo ")
        XCTAssertFalse(app.otherElements["mention-panel"].exists)
    }
    private func openBulkComments(_ app: XCUIApplication, flags: [String] = []) {
        app.launchArguments = ["--ui-tests", "--ui-tests-account", "--ui-tests-accepted-comments", "--ui-tests-bulk-delete"] + flags
        app.launch(); XCTAssertTrue(app.buttons["5 comments"].waitForExistence(timeout: 10)); app.buttons["5 comments"].tap()
        XCTAssertTrue(app.buttons["Select comments"].waitForExistence(timeout: 5))
    }
    private func attachBulkDraft(_ app: XCUIApplication, text: String) {
        let draft = app.textFields["comment-draft"]; XCTAssertTrue(draft.waitForExistence(timeout: 5)); draft.tap(); draft.typeText(text)
        app.buttons["Attach one of your posts"].tap()
        let tile = app.collectionViews.cells.firstMatch; XCTAssertTrue(tile.waitForExistence(timeout: 5)); tile.tap()
        XCTAssertTrue(app.buttons["remove-comment-attachment"].waitForExistence(timeout: 5))
    }
    private func confirmBulkDelete(_ app: XCUIApplication, count: Int) {
        app.buttons["Delete selected comments"].tap()
        let alert = app.alerts["Delete \(count) selected comments?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5)); alert.buttons["Delete"].tap()
    }
    private func assertCommentOptions(_ app: XCUIApplication, _ labels: [String], file: StaticString = #filePath, line: UInt = #line) {
        let alert = app.alerts["Comment options"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertEqual(alert.buttons.allElementsBoundByIndex.map(\.label).filter { $0 != "Cancel" }, labels, file: file, line: line)
    }
    private func previewRGB(_ element: XCUIElement, y: CGFloat) -> [UInt8] {
        guard let cg = element.screenshot().image.cgImage,
              let pixel = cg.cropping(to: CGRect(x: cg.width / 2, y: min(cg.height - 1, Int(CGFloat(cg.height) * y)), width: 1, height: 1)) else { XCTFail("Missing actual preview screenshot"); return [] }
        var pixels = [UInt8](repeating: 0, count: 4)
        pixels.withUnsafeMutableBytes { bytes in
            let context = CGContext(data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return Array(pixels.prefix(3))
    }
    func testInboundAttachmentCardsCropsUnavailableAndPublicRecoveryPreserveDraftAndBack() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-tests", "--ui-tests-account", "--ui-tests-attachment-cards"]; app.launch()
        XCTAssertTrue(app.buttons["3 comments"].waitForExistence(timeout: 10)); app.buttons["3 comments"].tap()
        let first = app.buttons["comment-attachment-Cards-0"], draft = app.textFields["comment-draft"]
        XCTAssertTrue(first.waitForExistence(timeout: 5)); XCTAssertFalse(app.buttons["comment-attachment-Cards-4"].exists, "The fifth incoming card must be excluded")
        XCTAssertEqual(first.frame.width / first.frame.height, 0.75, accuracy: 0.02)
        waitUntil("The actual comic preview must finish decoding") {
            let rgb = self.previewRGB(first, y: 0.25)
            return rgb.count == 3 && rgb[0] > 230 && rgb[1] < 30 && rgb[2] < 30
        }
        let top = previewRGB(first, y: 0.25), lower = previewRGB(first, y: 0.75)
        XCTAssertEqual(top.count, 3); XCTAssertEqual(lower.count, 3)
        XCTAssertTrue(top[0] > 230 && top[1] < 30 && top[2] < 30, "The first comic panel must be visible: \(top)")
        XCTAssertTrue(lower[2] > 230 && lower[0] < 30 && lower[1] < 30, "The card must crop, without stretching the whole strip: \(lower)")
        draft.tap(); draft.typeText("Attachment draft")
        first.tap(); XCTAssertEqual(app.keyboards.count, 0); XCTAssertTrue(app.otherElements["comments-screen"].exists)
        first.press(forDuration: 1)
        XCTAssertTrue(app.staticTexts["1 selected"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.tables.cells["comment-row-Cards"].value as? String, "Selected", "Holding a real multi-card hit rectangle selects its owning comment")
        app.buttons["Cancel comment selection"].tap()
        XCTAssertEqual(draft.value as? String, "Attachment draft")
        first.tap()
        XCTAssertTrue(app.buttons["8 smiles, smile"].waitForExistence(timeout: 5), "API404 must resolve the exact public picture before navigation")
        app.buttons["Back"].tap(); XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertEqual(draft.value as? String, "Attachment draft")
        XCTAssertEqual(app.otherElements["comments-screen"].value as? String, "api:AttachedPic,web:AttachedPic")
        func reveal(_ element: XCUIElement) {
            for _ in 0..<5 { if element.isHittable { break }; app.tables.firstMatch.swipeUp() }
            XCTAssertTrue(element.isHittable)
        }
        let gif = app.buttons["comment-attachment-Cards-1"]; reveal(gif)
        XCTAssertEqual(gif.value as? String, "GIF")
        let gone = app.buttons["comment-attachment-Cards-2"]; reveal(gone)
        XCTAssertEqual(gone.value as? String, "Post unavailable"); gone.tap()
        XCTAssertTrue(app.alerts["Post unavailable"].waitForExistence(timeout: 5)); app.alerts.buttons["OK"].tap()
        XCTAssertEqual(app.otherElements["comments-screen"].value as? String, "api:AttachedPic,web:AttachedPic", "Unavailable cards cannot issue another post request")
        let failed = app.buttons["comment-attachment-Cards-3"]; reveal(failed)
        XCTAssertEqual(failed.value as? String, "Preview unavailable - tap to open; VIDEO")
        failed.tap(); XCTAssertTrue(app.buttons["128 smiles, smile"].waitForExistence(timeout: 5)); app.buttons["Back"].tap()
        XCTAssertEqual(draft.value as? String, "Attachment draft")
        let withheld = app.descendants(matching: .any)["comment-body-Withheld"].firstMatch; reveal(withheld)
        XCTAssertEqual(withheld.label, "Post Unavailable")
        let abused = app.descendants(matching: .any)["comment-body-Abused"].firstMatch; reveal(abused)
        XCTAssertFalse(app.buttons["comment-attachment-Abused-0"].exists)
        abused.tap(); assertCommentOptions(app, ["Reply", "Report", "Remove"])
        app.alerts.buttons["Cancel"].tap(); capture("incoming-cards-unavailable-and-withheld", app: app)
        app.buttons["Refresh"].tap()
        let linked = app.buttons["comment-attachment-Withheld-0"]; reveal(linked)
        XCTAssertEqual(linked.value as? String, "VIDEO", "When primary content is empty, the link-derived cards must render")
        XCTAssertFalse(app.staticTexts["Post Unavailable"].exists, "A refreshed real attachment replaces the withheld placeholder")
        let blocked = app.buttons["comment-attachment-Withheld-1"]; reveal(blocked)
        XCTAssertEqual(blocked.value as? String, "Post unavailable", "A blocked creator is represented without fetching its thumbnail")
        XCTAssertEqual(draft.value as? String, "Attachment draft")
        capture("link-derived-cards-and-blocked-creator", app: app)
    }
    func testCommentTapRoleMenusReplyDepthDotsAndDraftRetention() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-tests", "--ui-tests-account", "--ui-tests-comment-options"]; app.launch()
        XCTAssertTrue(app.buttons["3 comments"].waitForExistence(timeout: 10)); app.buttons["3 comments"].tap()
        let root = app.staticTexts["The classic look is coming back."]
        XCTAssertTrue(root.waitForExistence(timeout: 5)); root.tap()
        assertCommentOptions(app, ["Reply", "Delete"])
        XCTAssertTrue(app.staticTexts["3 comments"].exists, "Ordinary row tap must keep the main list behind its options")
        app.alerts.buttons["Cancel"].tap()
        app.staticTexts["An attached post, right in the thread."].tap()
        assertCommentOptions(app, ["Reply", "Report", "Remove"])
        app.alerts.buttons["Remove"].tap()
        XCTAssertTrue(app.alerts["Remove this comment?"].waitForExistence(timeout: 5)); app.alerts.buttons["Cancel"].tap()
        app.descendants(matching: .any)["comment-replies-PreviewComment1"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Reply number one"].waitForExistence(timeout: 5))
        for id in ["PreviewReply1", "PreviewReply2"] {
            let dots = app.descendants(matching: .any)["comment-dots-" + id].firstMatch
            XCTAssertTrue(dots.exists); XCTAssertEqual(dots.label, "10 reply depth dots")
            XCTAssertEqual(dots.frame.width, 94, accuracy: 0.5, "Depth 29/30 must cap the actual dot strip at ten circles")
        }
        app.staticTexts["Reply number one"].tap(); assertCommentOptions(app, ["Reply", "Report", "Remove"])
        app.alerts.buttons["Reply"].tap()
        let draft = app.textFields["comment-draft"]
        waitUntil("Reply from the options must focus the composer") { app.keyboards.count > 0 }
        draft.typeText("Retained depth draft")
        XCTAssertEqual(app.staticTexts["reply-recipient"].label, "Reply to ReaderOne")
        app.staticTexts["Reply number two"].tap() // First outside tap only dismisses editing.
        XCTAssertFalse(app.alerts.firstMatch.exists); XCTAssertEqual(app.keyboards.count, 0)
        app.staticTexts["Reply number two"].tap(); assertCommentOptions(app, ["Report", "Remove"])
        capture("depth-30-options-and-capped-dots", app: app)
        app.alerts.buttons["Cancel"].tap()
        XCTAssertEqual(draft.value as? String, "Retained depth draft")
        XCTAssertEqual(app.staticTexts["reply-recipient"].label, "Reply to ReaderOne")
    }
    func testGuestCommentOptionsProfileAndSignedInOtherPostRole() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-tests", "--ui-tests-comment-options", "--ui-tests-profile"]; app.launch()
        XCTAssertTrue(app.buttons["3 comments"].waitForExistence(timeout: 10)); app.buttons["3 comments"].tap()
        let row = app.staticTexts["The classic look is coming back."]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        for id in ["comment-avatar-PreviewComment1", "comment-date-PreviewComment1"] {
            app.buttons[id].tap()
            XCTAssertTrue(app.collectionViews["profile-grid"].waitForExistence(timeout: 5), "Avatar and date route directly to the author profile")
            app.buttons["Back"].tap(); XCTAssertTrue(row.waitForExistence(timeout: 5))
        }
        XCTAssertTrue(row.waitForExistence(timeout: 5)); row.tap(); assertCommentOptions(app, ["Reply", "Profile", "Report"])
        app.alerts.buttons["Profile"].tap()
        XCTAssertTrue(app.collectionViews["profile-grid"].waitForExistence(timeout: 5), "Guests can open the comment author's profile")
        app.buttons["Back"].tap()
        app.descendants(matching: .any)["comment-replies-PreviewComment1"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Reply number one"].waitForExistence(timeout: 5)); XCTAssertFalse(app.alerts.firstMatch.exists)
        app.terminate()
        app.launchArguments = ["--ui-tests", "--ui-tests-account", "--ui-tests-comment-options", "--ui-tests-comment-other-owner"]; app.launch()
        XCTAssertTrue(app.buttons["3 comments"].waitForExistence(timeout: 10)); app.buttons["3 comments"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5)); row.tap(); assertCommentOptions(app, ["Reply", "Delete"])
        app.alerts.buttons["Cancel"].tap()
        app.staticTexts["Same feed. Familiar controls."].tap(); assertCommentOptions(app, ["Reply", "Profile", "Report"])
        app.alerts.buttons["Cancel"].tap()
        row.tap(); app.alerts.buttons["Reply"].tap()
        XCTAssertTrue(app.staticTexts["Reply number one"].waitForExistence(timeout: 5))
        waitUntil("Main-list Reply opens the thread with composer focus") { app.keyboards.count > 0 }
        XCTAssertFalse(app.staticTexts["reply-recipient"].exists, "Replying to the root uses the root endpoint without a nested recipient")
    }
    func testBulkPartialDeletionRemovesRootRepliesOnceAndRetainsFailedSelectionAndDraft() {
        let app = XCUIApplication(); openBulkComments(app, flags: ["--ui-tests-bulk-partial"])
        attachBulkDraft(app, text: "Bulk draft")
        app.buttons["Select comments"].tap()
        XCTAssertTrue(app.staticTexts["0 selected"].exists)
        let first = app.tables.cells["comment-row-PreviewComment1"], second = app.tables.cells["comment-row-PreviewComment2"]
        first.tap(); second.tap(); XCTAssertTrue(app.staticTexts["2 selected"].exists)
        confirmBulkDelete(app, count: 2)
        XCTAssertTrue(app.alerts["Some comments were not deleted"].waitForExistence(timeout: 5)); app.alerts.buttons["OK"].tap()
        XCTAssertFalse(first.exists); XCTAssertEqual(second.value as? String, "Selected"); XCTAssertTrue(app.staticTexts["1 selected"].exists)
        XCTAssertEqual(app.textFields["comment-draft"].value as? String, "Bulk draft"); XCTAssertTrue(app.buttons["remove-comment-attachment"].exists)
        XCTAssertEqual(app.otherElements["comments-screen"].value as? String, "selected=PreviewComment2; request=1|POST|/v4/content/PreviewPost/comments?method=DELETE|id=PreviewComment1,PreviewComment2")
        capture("partial-bulk-delete-retains-failed-row-and-draft", app: app)
        app.buttons["Cancel comment selection"].tap()
        XCTAssertTrue(app.staticTexts["2 comments"].exists, "Accepted root plus its two replies must leave two comments")
        app.buttons["Refresh"].tap(); XCTAssertTrue(second.waitForExistence(timeout: 5)); XCTAssertFalse(first.exists)
        XCTAssertEqual(app.textFields["comment-draft"].value as? String, "Bulk draft")
        app.buttons["Back"].tap(); XCTAssertTrue(app.buttons["2 comments"].waitForExistence(timeout: 5))
    }
    func testBulkReplyEmptyAcknowledgmentKeepsRootAndDeletedPositionsWithoutDoubleCount() {
        let app = XCUIApplication(); openBulkComments(app)
        app.descendants(matching: .any)["comment-replies-PreviewComment1"].firstMatch.tap()
        let root = app.tables.cells["comment-row-PreviewComment1"]
        XCTAssertTrue(root.waitForExistence(timeout: 5)); attachBulkDraft(app, text: "Reply draft")
        app.buttons["Select comments"].tap(); root.tap()
        XCTAssertTrue(app.staticTexts["0 selected"].exists, "The retained root context cannot enter a reply selection")
        app.tables.cells["comment-row-PreviewReply1"].tap(); app.tables.cells["comment-row-PreviewReply2"].tap()
        XCTAssertTrue(app.staticTexts["2 selected"].exists); confirmBulkDelete(app, count: 2)
        XCTAssertTrue(app.staticTexts["0 replies"].waitForExistence(timeout: 5)); XCTAssertTrue(root.exists)
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label == %@", "Comment was eaten by a black hole")).count, 2)
        XCTAssertFalse(app.descendants(matching: .any)["comment-dots-PreviewReply2"].firstMatch.exists, "Deleted reply positions have no depth strip")
        XCTAssertFalse(app.buttons["comment-smile-PreviewReply2"].exists)
        XCTAssertFalse(app.buttons["comment-avatar-PreviewReply2"].exists)
        XCTAssertEqual(app.otherElements["comments-screen"].value as? String, "selected=; request=1|POST|/v4/content/PreviewPost/comments?method=DELETE|id=PreviewReply1,PreviewReply2")
        XCTAssertEqual(app.textFields["comment-draft"].value as? String, "Reply draft"); XCTAssertTrue(app.buttons["remove-comment-attachment"].exists)
        app.buttons["Refresh"].tap(); XCTAssertTrue(root.waitForExistence(timeout: 5)); XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label == %@", "Comment was eaten by a black hole")).count, 2)
        capture("bulk-replies-root-and-deleted-placeholders", app: app)
        app.buttons["Back"].tap(); XCTAssertTrue(app.staticTexts["3 comments"].waitForExistence(timeout: 5))
        app.buttons["Back"].tap(); XCTAssertTrue(app.buttons["3 comments"].waitForExistence(timeout: 5))
    }
    func testAttachmentLongHoldSelectionAndUncertainDeletionRequireReadBeforeRetry() {
        let app = XCUIApplication(); openBulkComments(app, flags: ["--ui-tests-bulk-uncertain"])
        attachBulkDraft(app, text: "Keep after uncertainty")
        let picture = app.buttons["Open attached post"]
        XCTAssertTrue(picture.waitForExistence(timeout: 5)); picture.press(forDuration: 1)
        XCTAssertTrue(app.staticTexts["1 selected"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.tables.cells["comment-row-PreviewComment2"].value as? String, "Selected")
        confirmBulkDelete(app, count: 1)
        XCTAssertTrue(app.alerts["Deletion not confirmed"].waitForExistence(timeout: 5)); app.alerts.buttons["OK"].tap()
        XCTAssertFalse(app.buttons["Delete selected comments"].isEnabled)
        app.buttons["Delete selected comments"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertFalse(app.alerts.firstMatch.exists, "A disabled delete control cannot start another write")
        XCTAssertEqual(app.textFields["comment-draft"].value as? String, "Keep after uncertainty"); XCTAssertTrue(app.buttons["remove-comment-attachment"].exists)
        XCTAssertEqual(app.otherElements["comments-screen"].value as? String, "selected=PreviewComment2; request=1|POST|/v4/content/PreviewPost/comments?method=DELETE|id=PreviewComment2")
        capture("uncertain-bulk-delete-keeps-selection-and-draft", app: app)
        app.buttons["Cancel comment selection"].tap()
        XCTAssertTrue(app.alerts["oldFunny"].waitForExistence(timeout: 5)); app.alerts.buttons["OK"].tap()
        XCTAssertFalse(app.buttons["Select comments"].isEnabled, "A failed read cannot unlock an uncertain selection write")
        app.buttons["Refresh"].tap()
        waitUntil("Only a successful read unlocks selection again") { app.buttons["Select comments"].isEnabled }
        XCTAssertTrue(app.staticTexts["5 comments"].waitForExistence(timeout: 5)); XCTAssertTrue(app.tables.cells["comment-row-PreviewComment2"].exists)
        XCTAssertEqual(app.textFields["comment-draft"].value as? String, "Keep after uncertainty"); XCTAssertTrue(app.buttons["remove-comment-attachment"].exists)
    }
    func testMentionSelectionLinkAndUnconfirmedSendPreserveIdentityAndAttachment() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-tests", "--ui-tests-account", "--ui-tests-mentions"]; app.launch()
        XCTAssertTrue(app.buttons["3 comments"].waitForExistence(timeout: 10)); app.buttons["3 comments"].tap()
        chooseMention(app, prefix: "Hi ", defaults: true)
        let screen = app.otherElements["comments-screen"], draft = app.textFields["comment-draft"]
        XCTAssertTrue((screen.value as? String ?? "").hasPrefix("mentions=Reader2:3:11;"))
        app.buttons["Attach one of your posts"].tap()
        let tile = app.collectionViews.cells.firstMatch; XCTAssertTrue(tile.waitForExistence(timeout: 5)); tile.tap()
        XCTAssertTrue(app.buttons["remove-comment-attachment"].waitForExistence(timeout: 5))
        app.buttons["Back"].tap(); app.buttons["3 comments"].tap()
        XCTAssertEqual(draft.value as? String, "Hi ReaderTwo ")
        XCTAssertTrue((screen.value as? String ?? "").hasPrefix("mentions=Reader2:3:11;"))
        draft.tap()
        let body = app.descendants(matching: .any)["comment-body-PreviewComment1"].firstMatch
        XCTAssertTrue(body.waitForExistence(timeout: 5))
        let link = body.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 20, dy: 8))
        link.tap(); XCTAssertEqual(app.keyboards.count, 0); XCTAssertFalse(app.otherElements["user-profile"].exists)
        link.tap(); XCTAssertTrue(app.otherElements["user-profile"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["ReaderTwo"].exists, "The linked identity opens Reader2's profile")
        app.buttons["Back"].tap(); XCTAssertTrue(draft.waitForExistence(timeout: 5))
        XCTAssertEqual(draft.value as? String, "Hi ReaderTwo ")
        app.buttons["Send comment"].tap()
        XCTAssertTrue(app.alerts["Comment not confirmed"].waitForExistence(timeout: 5)); app.alerts.buttons["OK"].tap()
        XCTAssertEqual(draft.value as? String, "Hi ReaderTwo "); XCTAssertTrue(app.buttons["remove-comment-attachment"].exists)
        XCTAssertEqual(screen.value as? String, "mentions=Reader2:3:11; request=1|/v4/content/PreviewPost/comments|text=Hi ReaderTwo|mentions=Reader2:3:11|content=PreviewPost")
        capture("mention-unconfirmed-form-and-retained-draft", app: app)
        draft.tap(); draft.typeText(XCUIKeyboardKey.delete.rawValue)
        XCTAssertEqual(draft.value as? String, "Hi ReaderTwo")
        XCTAssertTrue((screen.value as? String ?? "").hasPrefix("mentions=Reader2:3:11;"), "Removing trailing space preserves the identity")
        draft.typeText(XCUIKeyboardKey.delete.rawValue)
        XCTAssertEqual(draft.value as? String, "Hi ReaderTw")
        XCTAssertTrue((screen.value as? String ?? "").hasPrefix("mentions=; request="), "Editing inside the name removes the chosen identity")
        draft.typeText("oxy" + XCUIKeyboardKey.delete.rawValue + XCUIKeyboardKey.delete.rawValue)
        XCTAssertEqual(draft.value as? String, "Hi ReaderTwo", "Rapid consecutive deletions must both reach the actual text field")
        XCTAssertTrue((screen.value as? String ?? "").hasPrefix("mentions=; request="), "Typing the old nickname does not restore its identity")
    }
    func testConfirmedMentionReplyUsesSelectedRecipientAndClearsOnlySubmittedDraft() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-tests", "--ui-tests-account", "--ui-tests-mentions", "--ui-tests-mention-success", "--ui-tests-accepted-comments"]; app.launch()
        XCTAssertTrue(app.buttons["5 comments"].waitForExistence(timeout: 10)); app.buttons["5 comments"].tap()
        let replies = app.descendants(matching: .any)["comment-replies-PreviewComment1"].firstMatch; XCTAssertTrue(replies.waitForExistence(timeout: 5)); replies.tap()
        let recipient = app.staticTexts["Reply number one"]; XCTAssertTrue(recipient.waitForExistence(timeout: 5)); recipient.tap(); app.alerts["Comment options"].buttons["Reply"].tap()
        chooseMention(app, prefix: "Hello ")
        XCTAssertEqual(app.staticTexts["reply-recipient"].label, "Reply to ReaderOne")
        app.buttons["Attach one of your posts"].tap()
        let tile = app.collectionViews.cells.firstMatch; XCTAssertTrue(tile.waitForExistence(timeout: 5)); tile.tap()
        app.buttons["Send comment"].tap()
        let sent = app.descendants(matching: .any)["comment-body-FixtureSentReply1"].firstMatch
        XCTAssertTrue(sent.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(sent.label, "Hello ReaderTwo")
        XCTAssertTrue((app.otherElements["comments-screen"].value as? String ?? "").contains("request=1|/v4/content/PreviewPost/comments/PreviewReply1/replies|text=Hello ReaderTwo|mentions=Reader2:6:14|content=PreviewPost"))
        XCTAssertFalse(app.staticTexts["reply-recipient"].exists); XCTAssertFalse(app.buttons["remove-comment-attachment"].exists)
        XCTAssertEqual(app.textFields["comment-draft"].value as? String, "Say something funny…")
        XCTAssertTrue(app.staticTexts["3 replies"].firstMatch.exists)
        capture("confirmed-mention-reply", app: app)
    }
    func testLongGIFUsesDecodedPixelsUnevenTimingLoopAndRetainedPhase() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-tests", "--ui-tests-gif"]; app.launch()
        let gif = app.descendants(matching: .any)["post-gif"].firstMatch
        XCTAssertTrue(gif.waitForExistence(timeout: 10), app.debugDescription)
        waitUntil("The 82nd GIF frame must actually decode; a long GIF must not become a still", timeout: 12) {
            let fields = self.gifFields(gif), rgb = (fields["pixel"] ?? "").split(separator: ",").compactMap { Int($0) }
            let phase = Double(fields["elapsed"] ?? "-1")?.truncatingRemainder(dividingBy: 7580) ?? -1
            return fields["frame"] == "81" && phase >= 5080 && phase < 7580 && rgb.count == 3 && rgb[2] > 150 && rgb[0] < 100 && rgb[1] < 100
        }
        var fields = gifFields(gif)
        XCTAssertEqual(fields["count"], "82"); XCTAssertEqual(Int(fields["duration"] ?? "") ?? -1, 7580, accuracy: 5)
        capture("long-gif-decoded-last-frame", app: app)
        waitUntil("GIF must loop to its long green second frame", timeout: 12) {
            let fields = self.gifFields(gif), rgb = (fields["pixel"] ?? "").split(separator: ",").compactMap { Int($0) }
            return fields["frame"] == "1" && rgb.count == 3 && rgb[1] > 150 && rgb[0] < 100 && rgb[2] < 100
        }
        fields = gifFields(gif); let before = Int(fields["elapsed"] ?? "") ?? -1
        app.buttons["3 comments"].tap(); XCTAssertTrue(app.textFields["comment-draft"].waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 3)
        app.buttons["Back"].tap(); XCTAssertTrue(gif.waitForExistence(timeout: 5))
        let after = Int(gifFields(gif)["elapsed"] ?? "") ?? -1
        XCTAssertGreaterThanOrEqual(after, before); XCTAssertLessThan(after - before, 2500, "The three inactive seconds must not advance retained GIF phase")
        capture("gif-retained-after-comments", app: app)
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
        app.buttons["Add tags"].tap()
        let tags = app.textFields["profile-tag-input"]; XCTAssertTrue(tags.waitForExistence(timeout: 5)); tags.tap(); tags.typeText("dogs\n")
        app.buttons["Back"].tap(); XCTAssertTrue(app.buttons["Remove tag dogs"].waitForExistence(timeout: 5))
        app.buttons["profile-media-filter"].tap(); app.buttons["Images"].tap()
        app.buttons["profile-author-filter"].tap()
        let search = app.textFields["user-search"]; XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeText("Writer")
        let writer = app.tables.cells["user-row-Writer"]; XCTAssertTrue(writer.waitForExistence(timeout: 5)); writer.tap()
        let collection = app.collectionViews["profile-grid"]
        waitUntil("The profile search must find all four source-backed Writer posts", details: { collection.debugDescription }) { collection.value as? String == "4 posts" }
        XCTAssertTrue(collection.cells["grid-post-GridPost5"].exists)
        app.buttons["Include republished posts"].tap()
        // Android suspends the retained author predicate with repubs disabled.
        // The fixture has 22 dog-tagged posts, four backed by source objects.
        waitUntil("Repubs off must retain 18 direct dog posts and suspend the author filter", details: { collection.debugDescription }) { collection.value as? String == "18 posts" }
        print("Offline filtered grid: data source=\(collection.value as? String ?? "missing"), accessibility cells=\(collection.cells.count)")
        XCTAssertTrue(collection.cells["grid-post-GridPost1"].exists)
        XCTAssertFalse(collection.cells["grid-post-GridPost5"].exists)
        XCTAssertFalse(app.buttons["profile-author-filter"].isEnabled)
        let lastDirect = collection.cells["grid-post-GridPost43"]
        for _ in 0..<4 { if lastDirect.isHittable { break }; collection.swipeUp() }
        XCTAssertTrue(lastDirect.isHittable, "All direct results must remain reachable in the actual grid")
        app.buttons["Include republished posts"].tap()
        waitUntil("Author selection and matches must return with repubs", details: { collection.debugDescription }) { collection.value as? String == "4 posts" }
        XCTAssertTrue(collection.cells["grid-post-GridPost5"].isHittable, "Changed filters reset to the beginning")
        app.buttons["Search options"].tap(); app.buttons["Clear filters"].tap()
        waitUntil("Clearing filters reuses already-scanned timeline pages", details: { collection.debugDescription }) { collection.value as? String == "44 posts" }
        XCTAssertTrue(collection.cells["grid-post-GridPost0"].isHittable)
        capture("profile-search-restored-results", app: app)
    }
    func testProfileTagSuggestionsLimitRemovalAndPendingBackCommit() {
        let app = XCUIApplication(); openOfflineProfile(app)
        app.buttons["Advanced Search"].tap(); app.buttons["Add tags"].tap()
        let input = app.textFields["profile-tag-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5)); input.typeText("do")
        let dogs = app.tables.cells["suggested-tag-dogs"]
        XCTAssertTrue(dogs.waitForExistence(timeout: 5)); dogs.tap()
        input.tap(); input.typeText("cats fun extra fifth ")
        XCTAssertEqual(app.staticTexts["profile-tags-remaining"].label, "0 tags remaining")
        input.typeText("pending"); app.buttons["Remove tag fun"].tap()
        XCTAssertEqual(input.value as? String, "pending", "Removing a chip must preserve unfinished input")
        XCTAssertEqual(app.staticTexts["profile-tags-remaining"].label, "1 tags remaining")
        app.buttons["Back"].tap()
        XCTAssertTrue(app.buttons["Remove tag pending"].waitForExistence(timeout: 5)); XCTAssertFalse(app.buttons["Remove tag fun"].exists)
        XCTAssertTrue(app.buttons["Remove tag pending"].isHittable, "Wrapped selected tags must expand the search header")
        XCTAssertTrue(app.buttons["Add tags"].isHittable, "The repub button must not clamp the wrapping tag row to its own height")
        app.buttons["Add tags"].tap(); app.buttons["Clear recent tags"].tap()
        XCTAssertTrue(app.buttons["Remove tag pending"].exists, "Clearing recent tags must preserve the current filter")
        app.buttons["Back"].tap(); capture("profile-tag-chips-after-back", app: app)
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
    func testConfirmedReplyAndRootDeletionCloseThreadAndRemoveRepliesFromPostTotalOnce() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-tests", "--ui-tests-account", "--ui-tests-accepted-comments"]; app.launch()
        XCTAssertTrue(app.buttons["5 comments"].waitForExistence(timeout: 10)); app.buttons["5 comments"].tap()
        let replies = app.descendants(matching: .any)["comment-replies-PreviewComment1"].firstMatch
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
        app.descendants(matching: .any)["comment-replies-PreviewComment1"].firstMatch.tap()
        XCTAssertTrue(root.waitForExistence(timeout: 5)); root.press(forDuration: 1)
        app.buttons["Delete"].tap()
        XCTAssertTrue(app.alerts["Delete this comment?"].waitForExistence(timeout: 5)); app.alerts.buttons["Delete"].tap()
        XCTAssertTrue(app.staticTexts["2 comments"].waitForExistence(timeout: 5), "Deleting root plus three replies must close the reply screen and leave two comments")
        XCTAssertFalse(root.exists); XCTAssertFalse(app.staticTexts["3 replies"].exists)
        XCTAssertTrue(app.staticTexts["An attached post, right in the thread."].exists)
        app.buttons["Refresh"].tap(); XCTAssertTrue(app.staticTexts["2 comments"].waitForExistence(timeout: 5))
        XCTAssertFalse(root.exists)
        capture("root-deletion-returns-and-removes-thread-total", app: app)
        app.buttons["Back"].tap()
        XCTAssertTrue(app.buttons["2 comments"].waitForExistence(timeout: 5))
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
        let replies = app.descendants(matching: .any)["comment-replies-PreviewComment1"].firstMatch
        XCTAssertTrue(replies.waitForExistence(timeout: 5)); replies.tap()
        let reply = app.staticTexts["Reply number one"]
        XCTAssertTrue(reply.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["The classic look is coming back."].exists)
        reply.tap(); app.alerts["Comment options"].buttons["Reply"].tap()
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
