import XCTest
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import OldFunnyCore

private struct DeletionStore: CredentialStore {
    func read() throws -> Credential? { try Credential(accessToken: "offline-bulk", refreshToken: "offline-refresh", accountID: "Owner", nickname: "Owner") }
    func write(_ credential: Credential) throws { throw ClientError.invalidInput }
    func erase() throws {}
}
private actor DeletionTransport: HTTPTransport {
    let result: HTTPResult
    private var requests = [URLRequest]()
    init(_ result: HTTPResult) { self.result = result }
    func send(_ request: URLRequest) async throws -> HTTPResult { requests.append(request); return result }
    func recorded() -> [URLRequest] { requests }
}

final class CommentDeletionTests: XCTestCase {
    func testModerationBelongsToOriginalAuthorRatherThanRepublisher() throws {
        let original = try Post(JSON.decode(Data(#"{"id":"Post","creator":{"id":"Original","nick":"Original"}}"#.utf8)))
        let republished = try Post(JSON.decode(Data(#"{"id":"Post","creator":{"id":"Republisher","nick":"Republisher"},"source":{"creator":{"id":"Original","nick":"Original"}}}"#.utf8)))
        XCTAssertEqual(original.moderationOwnerID, "Original")
        XCTAssertEqual(republished.authorID, "Republisher"); XCTAssertEqual(republished.moderationOwnerID, "Original")
        let missingOriginal = try Post(JSON.decode(Data(#"{"id":"Post","creator":{"id":"Republisher"},"source":{}}"#.utf8)))
        XCTAssertNil(missingOriginal.moderationOwnerID, "An omitted original author must not grant moderation to the republisher")
    }
    func testCapturedEmptyAcknowledgmentAcceptsExactlyTheRequestedUniqueSelection() throws {
        let response = try JSON.decode(Data(#"{"data":{"responses":[]},"status":200}"#.utf8))
        for count in [1, 2, 4] {
            let ids = (1...count).map { "Comment\($0)" }, receipt = try CommentDeletionReceipt(response, requested: ids)
            XCTAssertEqual(receipt.acceptedIDs, ids); XCTAssertTrue(receipt.remainingIDs.isEmpty)
        }
        for ids in [[], ["One", "One"], [""], ["null"], [" One"], ["One,Two"], ["bad:id"]] {
            XCTAssertThrowsError(try CommentDeletionReceipt(response, requested: ids))
        }
    }
    func testPartialReceiptsKeepRejectedMissingAndMalformedRowsSelected() throws {
        let response = try JSON.decode(Data(#"{"status":200,"data":{"responses":[{"status":200},{"status":204},{"status":403},{"status":299},{"status":300},{"status":200.5},{}]}}"#.utf8))
        let ids = (0..<8).map { "Comment\($0)" }, receipt = try CommentDeletionReceipt(response, requested: ids)
        XCTAssertEqual(receipt.acceptedIDs, ["Comment0", "Comment1", "Comment3"])
        XCTAssertEqual(receipt.remainingIDs, ["Comment2", "Comment4", "Comment5", "Comment6", "Comment7"])
    }
    func testUnknownEnvelopeNeverCreatesSuccessfulDeletionReceipts() throws {
        for text in ["null", "{}", #"{"status":200}"#, #"{"status":200,"data":{}}"#,
                     #"{"status":200,"data":{"responses":null}}"#, #"{"data":{"responses":[]}}"#,
                     #"{"status":403,"data":{"responses":[]}}"#, #"{"status":200.5,"data":{"responses":[]}}"#,
                     #"{"status":200,"data":{"responses":[{"status":204},{"status":204}]}}"#] {
            XCTAssertThrowsError(try CommentDeletionReceipt(JSON.decode(Data(text.utf8)), requested: ["One"]), text)
        }
    }
    func testBulkRequestUsesAndroidOverrideAndNeverReplaysUnauthorizedWrite() async throws {
        let transport = DeletionTransport(HTTPResult(status: 401, body: Data()))
        let api = try APIClient(installation: String(repeating: "a", count: 64), userAgent: "offline", store: DeletionStore(), transport: transport)
        let epoch = await api.sessionEpoch()
        do { _ = try await api.deleteComments(postID: "Post", commentIDs: ["One", "Two"], session: epoch); XCTFail() }
        catch { XCTAssertEqual(error as? ClientError, .http(401)) }
        let requests = await transport.recorded(); XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].httpMethod, "POST"); XCTAssertEqual(requests[0].url!.path, "/v4/content/Post/comments")
        XCTAssertEqual(URLComponents(url: requests[0].url!, resolvingAgainstBaseURL: false)?.queryItems, [URLQueryItem(name: "method", value: "DELETE")])
        XCTAssertEqual(String(decoding: requests[0].httpBody!, as: UTF8.self), "id=One%2CTwo")
        try await api.forgetSession()
        do { _ = try await api.deleteComments(postID: "Post", commentIDs: ["One"], session: epoch); XCTFail() }
        catch { XCTAssertEqual(error as? ClientError, .sessionChanged) }
        let final = await transport.recorded(); XCTAssertEqual(final.count, 1)
    }
}
