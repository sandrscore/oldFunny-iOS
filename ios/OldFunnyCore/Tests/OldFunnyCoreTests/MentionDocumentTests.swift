import XCTest
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import OldFunnyCore

private struct MentionStore: CredentialStore {
    let value: Credential?
    func read() throws -> Credential? { value }
    func write(_ credential: Credential) throws { throw ClientError.invalidInput }
    func erase() throws {}
}
private actor MentionTransport: HTTPTransport {
    private var replies: [HTTPResult], requests = [URLRequest]()
    init(_ replies: [HTTPResult]) { self.replies = replies }
    func send(_ request: URLRequest) async throws -> HTTPResult {
        requests.append(request); guard !replies.isEmpty else { throw ClientError.transport }; return replies.removeFirst()
    }
    func recorded() -> [URLRequest] { requests }
}
private func mentionClient(_ transport: MentionTransport, signedIn: Bool = true) throws -> APIClient {
    let identity = signedIn ? try Credential(accessToken: "mention-fixture", refreshToken: nil, accountID: "FixtureUser", nickname: "Fixture") : nil
    return try APIClient(installation: String(repeating: "a", count: 64), userAgent: "fixture", store: MentionStore(value: identity), transport: transport)
}

final class MentionDocumentTests: XCTestCase {
    func testMentionReadEndpointsAndLimitsUseAuthenticatedRequestsWithExactQuery() async throws {
        let raw = Data(#"{"status":200,"data":{"users":{"items":[],"paging":{"hasNext":false}}}}"#.utf8)
        let transport = MentionTransport([HTTPResult(status: 200, body: raw), HTTPResult(status: 200, body: raw)])
        let api = try mentionClient(transport)
        _ = try await api.mentionUsers(); _ = try await api.mentionUsers(query: "Jo", next: "x +&")
        let requests = await transport.recorded()
        XCTAssertEqual(requests.map { $0.url!.path }, ["/v4/users/my/mention_users", "/v4/search/users_for_mentions"])
        XCTAssertEqual(requests.map { $0.value(forHTTPHeaderField: "Authorization") }, ["Bearer mention-fixture", "Bearer mention-fixture"])
        let first = URLComponents(url: requests[0].url!, resolvingAgainstBaseURL: false)!.queryItems!
        let second = URLComponents(url: requests[1].url!, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(first, [URLQueryItem(name: "limit", value: "9")])
        XCTAssertEqual(second.first { $0.name == "limit" }?.value, "20"); XCTAssertEqual(second.first { $0.name == "q" }?.value, "Jo")
        XCTAssertEqual(second.first { $0.name == "next" }?.value, "x +&")
        do { _ = try await api.mentionUsers(query: "j"); XCTFail() } catch { XCTAssertEqual(error as? ClientError, .invalidInput) }
        let anonymous = try mentionClient(transport, signedIn: false)
        do { _ = try await anonymous.mentionUsers(); XCTFail() } catch { XCTAssertEqual(error as? ClientError, .signInRequired) }
        let after = await transport.recorded(); XCTAssertEqual(after.count, 2)
    }
    func testMentionReplyFormTrimsASCIIAndShiftsUTF16OffsetsWithoutReplay() async throws {
        let transport = MentionTransport([HTTPResult(status: 204, body: Data())]), api = try mentionClient(transport)
        var document = MentionDocument(text: "  🙂 Bob \n"); try document.add(userID: "User1", nickname: "Bob", at: 5)
        let epoch = await api.sessionEpoch()
        try await api.sendComment(postID: "Post1", parentID: "Parent1", text: document.text, attachmentID: "Picture1", mentions: document.mentions, session: epoch)
        let requests = await transport.recorded(); XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].url!.path, "/v4/content/Post1/comments/Parent1/replies"); XCTAssertEqual(requests[0].httpMethod, "POST")
        let body = String(decoding: requests[0].httpBody!, as: UTF8.self).replacingOccurrences(of: "+", with: "%20")
        let fields = URLComponents(string: "?" + body)!.queryItems!
        XCTAssertEqual(fields.first { $0.name == "text" }?.value, "🙂 Bob")
        XCTAssertEqual(fields.first { $0.name == "content" }?.value, "Picture1")
        XCTAssertEqual(fields.first { $0.name == "user_mentions" }?.value, "User1:3:5")
        do { try await api.sendComment(postID: "Post1", text: "@Bob", session: epoch); XCTFail() } catch { XCTAssertEqual(error as? ClientError, .transport) }
        let attempted = await transport.recorded(); XCTAssertEqual(attempted.count, 2)
        XCTAssertFalse(String(decoding: attempted[1].httpBody!, as: UTF8.self).contains("user_mentions"), "Plain @text never notifies a guessed identity")
        try await api.forgetSession()
        do { try await api.sendComment(postID: "Post1", text: "Bob", mentions: document.mentions, session: epoch); XCTFail() } catch { XCTAssertEqual(error as? ClientError, .sessionChanged) }
        let final = await transport.recorded(); XCTAssertEqual(final.count, 2)
    }
    func testMentionUserSchemaFiltersUnsafeRowsDedupesAndShowsMutualOnlyForBothFlags() throws {
        let data = try JSON.decode(Data(#"{"users":{"items":[{"id":"User1","nick":"José_1","photo":{"thumb":{"small_url":"http://unsafe.invalid/a","medium_url":"https://safe.invalid/b"}},"is_in_subscribers":true,"is_in_subscriptions":true},{"id":"User1","nick":"Duplicate"},{"id":"User2","nick":"Other","is_in_subscriptions":true},{"id":"User3","nick":"Blocked","is_blocked":true},{"id":"User4","nick":"Banned","is_banned":true},{"id":"User5","nick":"Deleted","is_deleted":true},{"id":"bad:id","nick":"Bad"},{"id":"User6","nick":"has space"}],"paging":{"hasNext":true,"cursors":{"next":"more"}}}}"#.utf8))
        let page = try MentionUserPage(data)
        XCTAssertEqual(page.users.map(\.id), ["User1", "User2"]); XCTAssertEqual(page.paging.next, "more")
        XCTAssertEqual(page.users[0].avatarURL?.absoluteString, "https://safe.invalid/b")
        XCTAssertTrue(page.users[0].mutual); XCTAssertFalse(page.users[1].mutual)
        XCTAssertThrowsError(try MentionUserPage(JSON.decode(Data(#"{"users":{"items":[]}}"#.utf8))))
    }
    func testCommentParsesMentionsAlongsideAttachmentAndDraftRetainsNewerIdentityRevision() throws {
        let comment = try Comment(JSON.decode(Data(#"{"id":"Comment1","text":"🙂 Bob","attachments":{"mention_user":[{"user_id":"User1","nick":"Bob","start_index":3,"stop_index":5}],"content":[{"id":"Picture1","type":"pic"}]}}"#.utf8)))
        XCTAssertEqual(comment.mentions.count, 1); XCTAssertEqual(comment.attachments.count, 1)
        var document = MentionDocument(text: comment.text, mentions: comment.mentions), draft = CommentDraft()
        draft.edit(document); let submitted = draft.revision
        XCTAssertTrue(document.replace(NSRange(location: 6, length: 0), with: "!")); draft.edit(document)
        draft.clear(ifRevision: submitted); XCTAssertEqual(draft.mentions.count, 1); XCTAssertEqual(draft.text, "🙂 Bob!")
        draft.edit(draft.text); XCTAssertEqual(draft.mentions.count, 1, "Same-text send snapshot preserves the selected identity")
        draft.edit("🙂 Rob!"); XCTAssertTrue(draft.mentions.isEmpty)
    }
    func testUTF16EmojiRangesAndInclusiveWireAndASCIITrim() throws {
        var document = MentionDocument(text: " \t🙂 Bob \n")
        try document.add(userID: "User1", nickname: "Bob", at: 5)
        XCTAssertEqual(document.wire(), "User1:5:7")
        XCTAssertEqual(document.wire(for: MentionDocument.asciiTrim(document.text)), "User1:3:5")
        XCTAssertNil(document.wire(for: "🙂 BOB"))
        XCTAssertEqual(MentionDocument.asciiTrim("\u{a0}Bob\u{a0}"), "\u{a0}Bob\u{a0}", "Java trim removes ASCII <=32 only")
    }
    func testInsertionShiftsNamesAndInteriorEditRemovesOnlyAffectedIdentity() throws {
        var document = MentionDocument(text: "Bob Sue")
        try document.add(userID: "User1", nickname: "Bob", at: 0); try document.add(userID: "User2", nickname: "Sue", at: 4)
        XCTAssertTrue(document.replace(NSRange(location: 0, length: 0), with: "🙂 "))
        XCTAssertEqual(document.wire(), "User1:3:5;User2:7:9")
        XCTAssertTrue(document.replace(NSRange(location: 6, length: 0), with: "!"))
        XCTAssertEqual(document.wire(), "User1:3:5;User2:8:10")
        XCTAssertTrue(document.replace(NSRange(location: 4, length: 1), with: "a"))
        XCTAssertEqual(document.text, "🙂 Bab! Sue"); XCTAssertEqual(document.wire(), "User2:8:10")
        let snapshot = document
        XCTAssertFalse(document.replace(NSRange(location: 1, length: 0), with: "x")); XCTAssertEqual(document, snapshot)
    }
    func testTokenExcludesEmailsSelectionsIdentifiedNamesAndJavaWhitespaceExceptions() {
        XCTAssertEqual(MentionDocument(text: "@").token(cursor: 1, selectionEnd: 1)?.query, "")
        XCTAssertNil(MentionDocument(text: "x@jo").token(cursor: 4, selectionEnd: 4))
        XCTAssertNil(MentionDocument(text: " @jo").token(cursor: 4, selectionEnd: 3))
        XCTAssertNil(MentionDocument(text: "\u{a0}@jo").token(cursor: 4, selectionEnd: 4))
        XCTAssertEqual(MentionDocument(text: "\u{2003}@jo").token(cursor: 4, selectionEnd: 4)?.query, "jo")
        XCTAssertNil(MentionDocument(text: "@😀").token(cursor: 3, selectionEnd: 3))
        XCTAssertNotNil(MentionDocument(text: "@" + String(repeating: "a", count: 25)).token(cursor: 26, selectionEnd: 26))
        XCTAssertNil(MentionDocument(text: "@" + String(repeating: "a", count: 26)).token(cursor: 27, selectionEnd: 27))
        let identified = MentionDocument(text: "@Bob", mentions: [MentionSpan(userID: "User1", nickname: "Bob", start: 1, end: 4)])
        XCTAssertNil(identified.token(cursor: 3, selectionEnd: 3))
    }
    func testChooseReplacesWholeTokenIncludingSuffixAndNeverInfersPlainTextIdentity() throws {
        var document = MentionDocument(text: "Hi @joSuffix")
        let token = try XCTUnwrap(document.token(cursor: 6, selectionEnd: 6))
        XCTAssertEqual(token.query, "jo"); XCTAssertEqual(token.end, 12)
        let end = try document.choose(token, userID: "User7", nickname: "Reader", cursor: 6)
        XCTAssertEqual(document.text, "Hi Reader "); XCTAssertEqual(end, 10); XCTAssertEqual(document.wire(), "User7:3:8")
        XCTAssertNil(MentionDocument(text: "Hi @Reader ").wire())
        let snapshot = document
        XCTAssertThrowsError(try document.choose(token, userID: "User7", nickname: "Other", cursor: 6)); XCTAssertEqual(document, snapshot)
    }
    func testInvalidChoiceIsAtomicAnd300UTF16LimitIsEnforced() throws {
        var document = MentionDocument(text: "@jo")
        let token = try XCTUnwrap(document.token(cursor: 3, selectionEnd: 3)), snapshot = document
        XCTAssertThrowsError(try document.choose(token, userID: "bad:id", nickname: "Reader", cursor: 3)); XCTAssertEqual(document, snapshot)
        document = MentionDocument(text: String(repeating: "x", count: 295) + " @jo")
        let long = try XCTUnwrap(document.token(cursor: 299, selectionEnd: 299))
        XCTAssertThrowsError(try document.choose(long, userID: "User1", nickname: "LongName", cursor: 299))
        XCTAssertEqual(document.text.utf16.count, 299)
    }
    func testIncomingMetadataRejectsFractionsOverlapsForgedNamesAndCanonicalLookalikes() throws {
        let data = try JSON.decode(Data(#"[{"user_id":"User1","nick":"Bob","start_index":3,"stop_index":5},{"user_id":"User2","nick":"ob","start_index":4,"stop_index":5},{"user_id":"User3","nick":"Bob","start_index":3.5,"stop_index":5},{"user_id":"User4","nick":"Wrong","start_index":3,"stop_index":5},{"user_id":"User5","nick":"Å","start_index":11,"stop_index":11}]"#.utf8))
        let document = MentionDocument(text: "🙂 Bob and Å", data: data)
        XCTAssertEqual(document.mentions.count, 1); XCTAssertEqual(document.wire(), "User1:3:5")
        XCTAssertEqual(MentionDocument(text: "Bob", data: .null).mentions, [])
        XCTAssertThrowsError(try { () -> Void in var doc = document; try doc.add(userID: "User6", nickname: "ob", at: 4) }())
    }
}
