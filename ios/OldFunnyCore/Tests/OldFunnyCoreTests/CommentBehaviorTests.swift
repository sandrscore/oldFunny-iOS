import XCTest
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import OldFunnyCore

private struct CommentReadStore: CredentialStore {
    func read() throws -> Credential? { nil }
    func write(_ credential: Credential) throws { throw ClientError.invalidInput }
    func erase() throws {}
}
private actor CommentReadTransport: HTTPTransport {
    private var requests = [URLRequest]()
    func send(_ request: URLRequest) async throws -> HTTPResult {
        requests.append(request)
        return HTTPResult(status: 200, body: Data(#"{"status":200,"data":{"comments":{"items":[],"paging":{"hasNext":false}},"replies":{"items":[],"paging":{"hasNext":false}}}}"#.utf8))
    }
    func recorded() -> [URLRequest] { requests }
}

final class CommentBehaviorTests: XCTestCase {
    func testDialogOrderFollowsOwnCommentOriginalPostOwnerAndOtherOrGuestRoles() {
        XCTAssertEqual(CommentBehavior.options(authorID: "Me", originalAuthorID: "Other", accountID: "Me", depth: 0, inReplies: false), [.reply, .delete])
        XCTAssertEqual(CommentBehavior.options(authorID: "Me", originalAuthorID: "Me", accountID: "Me", depth: 0, inReplies: false), [.reply, .delete], "Own comment takes priority over post moderation")
        XCTAssertEqual(CommentBehavior.options(authorID: "Other", originalAuthorID: "Me", accountID: "Me", depth: 0, inReplies: false), [.reply, .report, .remove])
        XCTAssertEqual(CommentBehavior.options(authorID: "Other", originalAuthorID: "Original", accountID: "Republisher", depth: 0, inReplies: false), [.reply, .profile, .report])
        XCTAssertEqual(CommentBehavior.options(authorID: nil, originalAuthorID: nil, accountID: nil, depth: 0, inReplies: false), [.reply, .profile, .report])
    }
    func testDepthBoundaryRemovesOnlyReplyAndOnlyInAnswerDialogs() {
        XCTAssertEqual(CommentBehavior.options(authorID: "Me", originalAuthorID: "Other", accountID: "Me", depth: 29, inReplies: true), [.reply, .delete])
        XCTAssertEqual(CommentBehavior.options(authorID: "Me", originalAuthorID: "Other", accountID: "Me", depth: 30, inReplies: true), [.delete])
        XCTAssertEqual(CommentBehavior.options(authorID: "Other", originalAuthorID: "Me", accountID: "Me", depth: 31, inReplies: true), [.report, .remove])
        XCTAssertEqual(CommentBehavior.options(authorID: "Me", originalAuthorID: "Other", accountID: "Me", depth: 30, inReplies: false), [.reply, .delete])
    }
    func testReplyDotCountUsesDepthMinusOneAndCurrentPhoneTabletResourceBounds() {
        XCTAssertEqual([0, 1, 2, 11, 31].map { CommentBehavior.replyDots(depth: $0, shortestViewportSide: 393) }, [0, 0, 1, 10, 10])
        XCTAssertEqual(CommentBehavior.replyDots(depth: 17, shortestViewportSide: 600), 15)
        XCTAssertEqual(CommentBehavior.replyDots(depth: 17, shortestViewportSide: 599), 10)
        XCTAssertEqual(CommentBehavior.replyDots(depth: .max, shortestViewportSide: 393), 10)
        XCTAssertEqual(CommentBehavior.replyDots(depth: .min, shortestViewportSide: 393), 0)
    }
    func testRootAndReplyReadsUseNativeFortyRowPagesAndExactRootPaths() async throws {
        let transport = CommentReadTransport()
        let api = try APIClient(installation: String(repeating: "a", count: 64), userAgent: "offline", store: CommentReadStore(), transport: transport)
        _ = try await api.comments(postID: "Post", next: "cursor +&")
        _ = try await api.comments(postID: "Post", parentID: "Root")
        let requests = await transport.recorded()
        XCTAssertEqual(requests.map { $0.httpMethod }, ["GET", "GET"])
        XCTAssertEqual(requests.map { $0.url!.path }, ["/v4/content/Post/comments", "/v4/content/Post/comments/Root/replies"])
        for request in requests {
            XCTAssertEqual(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "limit" }?.value, "40")
            XCTAssertNil(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "from" }, "The native comment-read interface has limit/show/prev/next, no feed-source field")
        }
        XCTAssertEqual(URLComponents(url: requests[0].url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "next" }?.value, "cursor +&")
    }
}
