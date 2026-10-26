import XCTest
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import OldFunnyCore

private struct AttachmentStore: CredentialStore {
    func read() throws -> Credential? { try Credential(accessToken: "fixture-token", refreshToken: nil, accountID: "Me", nickname: "Fixture") }
    func write(_ credential: Credential) throws {}
    func erase() throws {}
}
private actor AttachmentTransport: HTTPTransport {
    private var responses: [HTTPResult], requests = [URLRequest]()
    init(_ responses: [HTTPResult]) { self.responses = responses }
    func send(_ request: URLRequest) async throws -> HTTPResult {
        requests.append(request); guard !responses.isEmpty else { throw ClientError.transport }; return responses.removeFirst()
    }
    func recorded() -> [URLRequest] { requests }
}
private actor HeldPictureTransport: HTTPTransport {
    private var pending: CheckedContinuation<HTTPResult, Error>?, observed: CheckedContinuation<Void, Never>?
    func send(_ request: URLRequest) async throws -> HTTPResult {
        try await withCheckedThrowingContinuation { pending = $0; observed?.resume(); observed = nil }
    }
    func waitUntilPending() async { if pending == nil { await withCheckedContinuation { observed = $0 } } }
    func finish(_ body: Data) { pending?.resume(returning: HTTPResult(status: 200, body: body)); pending = nil }
}
final class CommentAttachmentTests: XCTestCase {
    private func json(_ source: String) throws -> JSON { try JSON.decode(Data(source.utf8)) }
    private var html: Data { Data(#"<html><SCRIPT>window.__INITIAL_STATE__={"feed":{"items":[{"id":"Picture1","type":"picture","state":"published","url":"https://media.invalid/original.jpg","size":{"w":640,"h":12000},"title":"escaped \" } brace","creator":{"id":"Author1","nick":"Author","avatar":"https://media.invalid/avatar"},"smiles":8,"comments":3,"isFeatured":true,"thumb":{"p":"https://media.invalid/thumb","pSize":{"w":320,"h":800}},"tags":["cats",{"name":"fun"}]}]}};window.unrelated='never evaluate';</SCRIPT></html>"#.utf8) }
    private func api(_ transport: any HTTPTransport, web: any HTTPTransport) throws -> APIClient {
        try APIClient(installation: String(repeating: "a", count: 64), userAgent: "fixture", store: AttachmentStore(), transport: transport, publicPictureTransport: web)
    }
    func testBoundedCardsKeepUnavailableEntriesAndUseThumbnailOrderAndGeometry() throws {
        let data = try json(##"{"content":[{"id":"Deleted","state":"deleted","thumb":{"url":"https://media.invalid/never"}},{"id":"Blocked","creator":{"is_blocked":true}},{"type":"gif","thumb":{"proportional_url":"file:///private","large_url":"https://media.invalid/large","url":"https://media.invalid/next","proportional_size":{"w":320,"h":800}},"bg_color":"#AAbBcc"},{"id":"Video","type":"video_clip","video_clip":{"screen_url":"https://media.invalid/video"},"size":{"w":100000,"h":0}},{"id":"Fifth"}],"content_from_links":[{"id":"Ignored"}]}"##)
        let cards = CommentAttachment.parse(data)
        XCTAssertEqual(cards.count, 4); XCTAssertEqual(cards[0].id, "Deleted"); XCTAssertTrue(cards[0].unavailable); XCTAssertNil(cards[0].previewURL)
        XCTAssertTrue(cards[1].unavailable); XCTAssertEqual(cards[2].previewURL?.absoluteString, "https://media.invalid/large")
        XCTAssertEqual(cards[2].badge, "GIF"); XCTAssertEqual(cards[2].backgroundARGB, 0xffaabbcc)
        XCTAssertEqual(cards[2].width, 320); XCTAssertEqual(cards[2].height, 800); XCTAssertNil(cards[2].contentID)
        XCTAssertEqual(cards[3].badge, "VIDEO"); XCTAssertEqual(cards[3].width, 10000); XCTAssertEqual(cards[3].height, 1)
        XCTAssertEqual(cards[3].backgroundARGB, 0xff333337)
    }
    func testFallbackWithheldAndUnsafeURLDistinctionsMatchAndroid() throws {
        let data = try json(#"{"content":[null,{},12],"content_from_links":[{"id":"Linked","type":"pic","url":"https://media.invalid/image"}]}"#)
        XCTAssertEqual(CommentAttachment.parse(data).map(\.id), ["Linked"])
        XCTAssertTrue(CommentAttachment.isWithheld(try json(#"{"content":[],"content_from_links":[]}"#)))
        XCTAssertFalse(CommentAttachment.isWithheld(.null))
        XCTAssertFalse(CommentAttachment.isWithheld(try json(#"{"content":[],"giphy":[{}]}"#)))
        XCTAssertFalse(CommentAttachment.isWithheld(try json(#"{"content":[],"extra":null}"#)))
        for url in ["file:///private", "javascript:alert(1)", "https://user:pass@media.invalid/image", "https://media.invalid/space here", "https://media.invalid/bad%zz", "https://media.invalid/end%"] { XCTAssertNil(CommentAttachment.webURL(url)) }
        XCTAssertNotNil(CommentAttachment.webURL("https://media.invalid/space%20here"))
        XCTAssertNotNil(CommentAttachment.webURL("http://media.invalid/public"), "The Android adapter permits public HTTP previews")
        let abused = try Comment(json(#"{"id":"C","state":"abused","attachments":{"content":[]}}"#))
        XCTAssertTrue(abused.isAbused); XCTAssertTrue(abused.hasWithheldAttachments)
    }
    func testCropUsesFirstComicPanelCenteredVideoAndActualCompactAspectBounds() throws {
        for (w, h, expected) in [(400, 300, PreviewSize(width: 384, height: 288)), (300, 400, PreviewSize(width: 216, height: 288)), (640, 12000, PreviewSize(width: 216, height: 288)), (400, 400, PreviewSize(width: 288, height: 288)), (1600, 900, PreviewSize(width: 384, height: 216)), (400, 500, PreviewSize(width: 230, height: 288)), (4000, 100, PreviewSize(width: 384, height: 86))] {
            XCTAssertEqual(try CommentPreviewCrop.size(imageWidth: w, imageHeight: h, maxWidth: 384, minHeight: 86), expected)
        }
        XCTAssertEqual(try CommentPreviewCrop.source(imageWidth: 320, imageHeight: 800, width: 384, height: 288, fromTop: true), PreviewRect(left: 0, top: 0, right: 320, bottom: 240))
        XCTAssertEqual(try CommentPreviewCrop.source(imageWidth: 320, imageHeight: 800, width: 384, height: 288, fromTop: false), PreviewRect(left: 0, top: 280, right: 320, bottom: 520))
        XCTAssertEqual(try CommentPreviewCrop.source(imageWidth: 1600, imageHeight: 900, width: 384, height: 288, fromTop: true), PreviewRect(left: 200, top: 0, right: 1400, bottom: 900))
        XCTAssertThrowsError(try CommentPreviewCrop.source(imageWidth: 0, imageHeight: 800, width: 384, height: 288, fromTop: true))
    }
    func testPublicJSONRecoveryRequiresExactPublishedPictureAndDoesNotEvaluateScripts() throws {
        let post = try XCTUnwrap(PublicPicture.parse(html, id: "Picture1"))
        XCTAssertEqual(post.mediaURL?.absoluteString, "https://media.invalid/original.jpg"); XCTAssertEqual(post.height, 12000)
        XCTAssertEqual(post.authorID, "Author1"); XCTAssertEqual(post.tags, ["cats", "fun"]); XCTAssertEqual(post.smiles, 8)
        XCTAssertTrue(post.isFeatured); XCTAssertNotNil(post.authorAvatarURL); XCTAssertNotNil(post.posterURL)
        XCTAssertNil(try PublicPicture.parse(html, id: "Other"))
        for (a, b) in [("\"published\"", "\"deleted\""), ("\"picture\"", "\"video\""), ("\"state\":\"published\"", "\"state\":\"published\",\"isAbused\":true")] {
            XCTAssertNil(try PublicPicture.parse(Data(String(decoding: html, as: UTF8.self).replacingOccurrences(of: a, with: b).utf8), id: "Picture1"))
        }
        XCTAssertNil(try PublicPicture.parse(Data("<script>window.__INITIAL_STATE__={broken}".utf8), id: "Picture1"))
    }
    func testOnlyAPI404RecoversAndWebsiteRequestContainsNoAPIIdentity() async throws {
        let transport = AttachmentTransport([HTTPResult(status: 404, body: Data())]), web = AttachmentTransport([HTTPResult(status: 200, body: html)])
        let client = try api(transport, web: web); let post = try await client.content(postID: "Picture1")
        XCTAssertEqual(post.id, "Picture1")
        let requests = await transport.recorded(), publicRequests = await web.recorded()
        XCTAssertEqual(requests[0].httpMethod, "GET"); XCTAssertEqual(requests[0].url?.path, "/v4/content/Picture1")
        XCTAssertNotNil(requests[0].value(forHTTPHeaderField: "Authorization")); XCTAssertEqual(publicRequests.count, 1)
        XCTAssertEqual(publicRequests[0].url?.absoluteString, "https://ifunny.co/picture/Picture1")
        for header in ["Authorization", "Cookie", "iFunny-Installation-Id"] { XCTAssertNil(publicRequests[0].value(forHTTPHeaderField: header)) }
        let denied = AttachmentTransport([HTTPResult(status: 403, body: Data())]), unused = AttachmentTransport([])
        do { _ = try await api(denied, web: unused).content(postID: "Picture1"); XCTFail("Expected denied API read") }
        catch { XCTAssertEqual(error as? ClientError, .http(403)) }
        let untouched = await unused.recorded(); XCTAssertTrue(untouched.isEmpty)
    }
    func testPublicFallbackCannotReturnIntoChangedAccount() async throws {
        let transport = AttachmentTransport([HTTPResult(status: 404, body: Data())]), web = HeldPictureTransport()
        let client = try api(transport, web: web); let task = Task { try await client.content(postID: "Picture1") }
        await web.waitUntilPending(); try await client.forgetSession(); await web.finish(html)
        do { _ = try await task.value; XCTFail("A late public read must not change the new account's screen") }
        catch { XCTAssertEqual(error as? ClientError, .sessionChanged) }
    }
    func testDirectContentUsesExactIdentityAndNeverFallsBackOnMalformedSuccess() async throws {
        let transport = AttachmentTransport([
            HTTPResult(status: 200, body: Data(#"{"status":200,"data":{"id":"Picture1","type":"pic","url":"https://media.invalid/original.jpg","size":{"w":640,"h":480}}}"#.utf8)),
            HTTPResult(status: 200, body: Data(#"{"status":200,"data":{"id":"WrongPicture","type":"pic"}}"#.utf8)),
            HTTPResult(status: 200, body: Data(#"{"status":404,"data":{}}"#.utf8))
        ]), web = AttachmentTransport([])
        let client = try api(transport, web: web)
        let post = try await client.content(postID: "Picture1"); XCTAssertEqual(post.id, "Picture1")
        do { _ = try await client.content(postID: "Picture1"); XCTFail("Wrong identity must be rejected") }
        catch { XCTAssertEqual(error as? ClientError, .malformedResponse) }
        do { _ = try await client.content(postID: "Picture1"); XCTFail("An envelope error on HTTP200 is not the native HTTP404 fallback trigger") }
        catch { XCTAssertEqual(error as? ClientError, .http(404)) }
        let untouched = await web.recorded(); XCTAssertTrue(untouched.isEmpty)
        let requests = await transport.recorded()
        XCTAssertEqual(requests.count, 3); XCTAssertTrue(requests.allSatisfy { $0.url?.path == "/v4/content/Picture1" && $0.url?.query == nil })
    }
}
