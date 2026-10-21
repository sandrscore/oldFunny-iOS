import XCTest
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import OldFunnyCore

private final class ProfileStore: CredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var value: Credential?
    init(_ value: Credential?) { self.value = value }
    func read() throws -> Credential? { lock.lock(); defer { lock.unlock() }; return value }
    func write(_ value: Credential) throws { lock.lock(); defer { lock.unlock() }; self.value = value }
    func erase() throws { lock.lock(); defer { lock.unlock() }; value = nil }
}
private actor ProfileTransport: HTTPTransport {
    var replies: [HTTPResult], requests = [URLRequest]()
    init(_ replies: [HTTPResult]) { self.replies = replies }
    func send(_ request: URLRequest) async throws -> HTTPResult {
        requests.append(request); guard !replies.isEmpty else { throw ClientError.transport }; return replies.removeFirst()
    }
    func recorded() -> [URLRequest] { requests }
}
private func profileHTTP(_ json: String, status: Int = 200) -> HTTPResult { HTTPResult(status: status, body: Data(json.utf8)) }
private func profileClient(_ transport: ProfileTransport) throws -> APIClient {
    try APIClient(installation: String(repeating: "a", count: 64), userAgent: "fixture", store: ProfileStore(try Credential(accessToken: "profile-fixture", refreshToken: nil, accountID: "FixtureUser", nickname: "Fixture")), transport: transport)
}
private let noProfilePosts = #"{"status":200,"data":{"content":{"items":[],"paging":{"hasNext":false}}}}"#
private func pinPage(_ ids: [String]) -> HTTPResult {
    profileHTTP("{\"status\":200,\"data\":{\"content\":{\"items\":[" + ids.map { "{\"id\":\"\($0)\",\"type\":\"pic\",\"is_pinned\":true}" }.joined(separator: ",") + "],\"paging\":{\"hasNext\":false}}}}")
}
private func parsedPost(_ source: String) throws -> Post { try Post(JSON.decode(Data(source.utf8))) }

final class ProfilesTests: XCTestCase {
    func testProfileMediaTaxonomyMatchesAndroidRawTypes() {
        for type in ["pic", "text_pic", "caption", "mem", "dem", "comics", "old"] { XCTAssertEqual(ProfileMediaKind.category(type), .images) }
        for type in ["video", "video_clip", "text_video", "coub", "vine"] { XCTAssertEqual(ProfileMediaKind.category(type), .videos) }
        for type in ["gif", "gif_caption", "text_gif"] { XCTAssertEqual(ProfileMediaKind.category(type), .gifs) }
        XCTAssertEqual(ProfileMediaKind.category("text_post"), .text)
        XCTAssertNil(ProfileMediaKind.category("unknown"))
    }
    func testCombinedFiltersUseAllTagsAndOriginalAuthorNotViewerReactionFlag() throws {
        let original = try parsedPost(##"{"id":"Post1","type":"text_video","creator":{"id":"Owner","nick":"Owner"},"source":{"creator":{"id":"Writer","nick":"MixedCase"}},"tags":["#CaTs","DOGS"],"is_republished":false}"##)
        var query = ProfileSearchCriteria(); query.media = .videos; query.authorID = "Writer"; query.setTags(["cats", "#dogs", "CATS"])
        XCTAssertEqual(query.tags.count, 2); XCTAssertTrue(query.matches(original, profileID: "Owner"))
        query.authorID = "Owner"; XCTAssertFalse(query.matches(original, profileID: "Owner"))
        query.includeRepubs = false; XCTAssertFalse(query.matches(original, profileID: "Owner"))
        let direct = try parsedPost(#"{"id":"Post2","type":"text_video","creator":{"id":"Owner"},"tags":["cats","dogs"],"is_republished":true}"#)
        XCTAssertTrue(query.matches(direct, profileID: "Owner"), "Author predicate is suspended with repubs disabled; is_republished is not source presence")
        query.setTags(["cats", "missing"]); XCTAssertFalse(query.matches(direct, profileID: "Owner"))
    }
    func testMissingSourceAuthorNeverFallsBackToRepublisherAndSelfRepubIsExcluded() throws {
        let missing = try parsedPost(#"{"id":"Post1","type":"pic","creator":{"id":"Owner","nick":"Owner"},"source":{}}"#)
        var query = ProfileSearchCriteria(); query.authorID = "Owner"
        XCTAssertFalse(query.matches(missing, profileID: "Owner"))
        let selfRepub = try parsedPost(#"{"id":"Post2","type":"pic","creator":{"id":"Owner"},"source":{"creator":{"id":"Owner"}}}"#)
        query.includeRepubs = false; XCTAssertFalse(query.matches(selfRepub, profileID: "Owner"))
    }
    func testFeaturedGridFiltersOwnerFlagsAndRetainsStateOnCursorLoop() throws {
        let first = try PostPage(JSON.decode(Data(#"{"content":{"items":[{"id":"A","type":"pic","creator":{"id":"Owner"},"is_featured":true},{"id":"B","type":"pic","creator":{"id":"Other"},"is_featured":true},{"id":"C","type":"pic","creator":{"id":"Owner"},"is_featured":false}],"paging":{"cursors":{"next":"next1"}}}}"#.utf8)))
        var pages = ProfilePages(); try pages.apply(first, replacing: true, featuredOwner: "Owner")
        XCTAssertEqual(pages.posts.map(\.id), ["A"])
        XCTAssertThrowsError(try pages.apply(first, replacing: false, featuredOwner: "Owner")) { XCTAssertEqual($0 as? ProfileActionError, .cursorLoop) }
        XCTAssertEqual(pages.posts.map(\.id), ["A"]); XCTAssertEqual(pages.next, "next1")
    }
    func testPublicProfileFieldsAndUntrustedMediaURLs() throws {
        let user = try UserProfile(JSON.decode(Data(#"{"id":"Owner","nick":"Name","about":"About","avatar":{"s":"http://unsafe.invalid/a"},"cover_url":"https://example.invalid/cover","num":{"created":9,"featured":2,"subscribers":5,"subscriptions":8},"is_in_subscriptions":true,"is_banned":true,"is_deleted":false,"email":"never-rendered@example.invalid"}"#.utf8)))
        XCTAssertNil(user.avatarURL); XCTAssertEqual(user.coverURL?.scheme, "https")
        XCTAssertEqual(user.created, 9); XCTAssertEqual(user.featured, 2); XCTAssertTrue(user.isSubscribed); XCTAssertTrue(user.isDeleted)
    }
    func testProfileAndFeaturedAndUserListUseSeparateAndroidEndpoints() async throws {
        let users = #"{"status":200,"data":{"users":{"items":[{"id":"Other","nick":"Other"}],"paging":{"hasNext":false}}}}"#
        let transport = ProfileTransport([profileHTTP(#"{"status":200,"data":{"id":"Owner","nick":"Owner"}}"#), profileHTTP(noProfilePosts), profileHTTP(users), profileHTTP(users)])
        let api = try profileClient(transport)
        _ = try await api.profile(userID: "Owner"); _ = try await api.profileTimeline(userID: "Owner", featured: true, next: "x +&")
        _ = try await api.users(userID: "Owner", kind: .subscribers); _ = try await api.searchUsers("some +& name")
        let requests = await transport.recorded()
        XCTAssertEqual(requests.map { $0.url!.path }, ["/v4/users/Owner", "/v4/timelines/users/Owner/featured", "/v4/users/Owner/subscribers", "/v4/search/users"])
        let query = URLComponents(url: requests[1].url!, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(query.first { $0.name == "next" }?.value, "x +&")
    }
    func testWrongProfileIdentityAndMissingPagingAreRejected() async throws {
        let transport = ProfileTransport([profileHTTP(#"{"status":200,"data":{"id":"Wrong"}}"#), profileHTTP(#"{"status":200,"data":{"content":{"items":[]}}}"#)])
        let api = try profileClient(transport)
        do { _ = try await api.profile(userID: "Owner"); XCTFail() } catch { XCTAssertEqual(error as? ClientError, .malformedResponse) }
        do { _ = try await api.profileTimeline(userID: "Owner"); XCTFail() } catch { XCTAssertEqual(error as? ClientError, .malformedResponse) }
    }
    func testPinLimitPreventsWriteAndConfirmedPinUsesPreflightWriteReadback() async throws {
        let full = ProfileTransport([pinPage(["A", "B", "C"])]), api = try profileClient(full)
        let epoch = await api.sessionEpoch()
        do { _ = try await api.setProfilePin(userID: "FixtureUser", postID: "D", enabled: true, session: epoch); XCTFail() } catch { XCTAssertEqual(error as? ProfileActionError, .pinLimit) }
        let blocked = await full.recorded(); XCTAssertEqual(blocked.count, 1); XCTAssertEqual(blocked[0].httpMethod, "GET")
        let allowed = ProfileTransport([pinPage(["A"]), profileHTTP("", status: 204), pinPage(["A", "B"])])
        let second = try profileClient(allowed), session = await second.sessionEpoch()
        let result = try await second.setProfilePin(userID: "FixtureUser", postID: "B", enabled: true, session: session)
        XCTAssertEqual(result.posts.filter(\.isPinned).count, 2)
        let requests = await allowed.recorded(); XCTAssertEqual(requests.map(\.httpMethod), ["GET", "PUT", "GET"])
        XCTAssertEqual(requests[1].url!.path, "/v4/content/B/pinned")
    }
    func testLostPinAcknowledgementAndStaleSessionNeverReplayWrite() async throws {
        let transport = ProfileTransport([pinPage([])]), api = try profileClient(transport), epoch = await api.sessionEpoch()
        do { _ = try await api.setProfilePin(userID: "FixtureUser", postID: "B", enabled: true, session: epoch); XCTFail() } catch { XCTAssertEqual(error as? ClientError, .transport) }
        let attempted = await transport.recorded(); XCTAssertEqual(attempted.map(\.httpMethod), ["GET", "PUT"])
        try await api.forgetSession()
        do { _ = try await api.setProfilePin(userID: "FixtureUser", postID: "B", enabled: true, session: epoch); XCTFail() } catch { XCTAssertEqual(error as? ClientError, .sessionChanged) }
        let after = await transport.recorded(); XCTAssertEqual(after.count, 2)
    }
    func testSubscribeRequiresReadbackAndRefusesOwnProfileBeforeTransport() async throws {
        let transport = ProfileTransport([profileHTTP("", status: 204), profileHTTP(#"{"status":200,"data":{"id":"Other","is_in_subscriptions":false}}"#)])
        let api = try profileClient(transport), epoch = await api.sessionEpoch()
        do { _ = try await api.setSubscribed(userID: "FixtureUser", enabled: true, session: epoch); XCTFail() } catch { XCTAssertEqual(error as? ClientError, .invalidInput) }
        do { _ = try await api.setSubscribed(userID: "Other", enabled: true, session: epoch); XCTFail() } catch { XCTAssertEqual(error as? ProfileActionError, .unconfirmed) }
        let requests = await transport.recorded(); XCTAssertEqual(requests.map(\.httpMethod), ["PUT", "GET"])
        XCTAssertEqual(requests[0].url!.path, "/v4/users/Other/subscribers")
    }
}
