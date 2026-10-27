import XCTest
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import OldFunnyCore

private struct ExploreCredentials: CredentialStore {
    func read() throws -> Credential? { try Credential(accessToken: "offline-explore-fixture", refreshToken: nil, accountID: "Fixture", nickname: "Fixture") }
    func write(_ credential: Credential) throws {}
    func erase() throws {}
}
private actor ExploreHTTP: HTTPTransport {
    private var replies: [HTTPResult], requests = [URLRequest]()
    private var hold: Bool, held: CheckedContinuation<Void, Never>?, observed: CheckedContinuation<Void, Never>?
    init(_ values: [String], hold: Bool = false) { replies = values.map { HTTPResult(status: 200, body: Data($0.utf8)) }; self.hold = hold }
    func send(_ request: URLRequest) async throws -> HTTPResult {
        requests.append(request)
        if hold { hold = false; await withCheckedContinuation { held = $0; observed?.resume(); observed = nil } }
        guard !replies.isEmpty else { throw ClientError.transport }; return replies.removeFirst()
    }
    func waitUntilHeld() async { if held == nil { await withCheckedContinuation { observed = $0 } } }
    func finish() { held?.resume(); held = nil }
    func recorded() -> [URLRequest] { requests }
}
final class ExploreTests: XCTestCase {
    private let tags = #"{"status":200,"data":{"tags":{"items":[{"tag":"Cats","uses":3}]}}}"#
    private let posts = #"{"status":200,"data":{"content":{"items":[{"id":"TagPost","type":"pic"}],"paging":{"hasNext":false}}}}"#
    private func user(_ id: String, _ nick: String) throws -> UserProfile { try UserProfile(.object(["id": .string(id), "nick": .string(nick)])) }
    private func api(_ transport: ExploreHTTP) throws -> APIClient { try APIClient(installation: String(repeating: "a", count: 64), userAgent: "offline explore", store: ExploreCredentials(), transport: transport) }
    func testExploreKeepsExactTagsAndPreviewsWithoutNeedingAContentID() throws {
        let raw = #"{"tags":{"items":[{"tag":"Cats","uses":3,"content":{"thumb":{"small_url":"https://example.invalid/s","large_url":"https://example.invalid/l"}}},{"tag":"Cats"},{"tag":"cats"},{"tag":"🔎"},{"tag":""},{"tag":"bad\nvalue"}]}}"#
        let page = try ExplorePage(JSON.decode(Data(raw.utf8)))
        XCTAssertEqual(page.tiles.map(\.tag), ["Cats", "cats", "🔎"])
        XCTAssertEqual(page.tiles[0].previewURL?.path, "/l"); XCTAssertEqual(page.tiles[0].uses, 3)
        XCTAssertThrowsError(try ExplorePage(.object(["tags": .object([:])])))
        XCTAssertEqual(try TagFeed(tag: "Cats", kind: .trending).source, "trending:Cats")
        XCTAssertEqual(try TagFeed(tag: "Cats", kind: .channel).path, "channels")
    }
    func testMixedRecentsUseExactQueryAndTypeAndTenTotalWithTypeOnlyClearing() throws {
        var history = RecentSearchHistory()
        for n in 0..<12 { history.record(try RecentSearchEntry(tag: "Tag\(n)")) }
        history.record(RecentSearchEntry(user: try user("One", "Tag11")))
        history.record(try RecentSearchEntry(tag: "Tag11"))
        XCTAssertEqual(history.entries.count, 10)
        XCTAssertEqual(history.entries.prefix(2).map(\.kind), [.tag, .user])
        XCTAssertFalse(history.entries.contains { $0.query == "Tag0" })
        history.record(RecentSearchEntry(user: try user("One", "Renamed")))
        XCTAssertEqual(history.entries.filter { $0.userID == "One" }.count, 2, "Android identity is exact query+type, not UID")
        let restored = try RecentSearchHistory(data: history.encoded); XCTAssertEqual(restored, history)
        history.clear(.tag); XCTAssertEqual(history.entries.map(\.query), ["Renamed", "Tag11"])
        history.clear(); XCTAssertTrue(history.entries.isEmpty)
    }
    func testMalformedPersistedRecentEntriesCannotBecomeProfileOrURLTargets() throws {
        let raw = #"[{"kind":"user","query":"Forged","userID":"../Other","avatar":"https://example.invalid/a"},{"kind":"tag","query":"Cats"},{"kind":"user","query":"Reader","userID":"Reader","avatar":"file:///private/session"}]"#
        let history = try RecentSearchHistory(data: Data(raw.utf8))
        XCTAssertEqual(history.entries.map(\.query), ["Cats"])
        XCTAssertThrowsError(try RecentSearchHistory(data: Data(repeating: 32, count: 65537)))
        XCTAssertThrowsError(try RecentSearchHistory(data: Data("broken".utf8)))
    }
    func testExploreRoutesPreserveQueriesCursorsAndUseOnlyReadRequests() async throws {
        let transport = ExploreHTTP([tags, tags, posts, posts]), api = try api(transport)
        _ = try await api.explore(); _ = try await api.exploreTags("Ca")
        _ = try await api.tagFeed(TagFeed(tag: "Cats & Dogs", kind: .trending), next: "opaque/+&")
        _ = try await api.tagFeed(TagFeed(tag: "Meanwhile", kind: .channel))
        let requests = await transport.recorded()
        XCTAssertEqual(requests.map { $0.httpMethod }, ["GET", "GET", "GET", "GET"])
        XCTAssertEqual(requests.map { $0.url!.path }, ["/v4/tags/explore", "/v4/tags/suggested", "/v4/search/content", "/v4/channels"])
        func fields(_ index: Int) -> [URLQueryItem] { URLComponents(url: requests[index].url!, resolvingAgainstBaseURL: false)!.queryItems ?? [] }
        XCTAssertEqual(fields(1), [URLQueryItem(name: "q", value: "Ca")])
        XCTAssertEqual(fields(2), [URLQueryItem(name: "tag", value: "Cats & Dogs"), URLQueryItem(name: "limit", value: "30"), URLQueryItem(name: "next", value: "opaque/+&")])
        do { _ = try await api.exploreTags("x"); XCTFail("One UTF16 unit must not request suggestions") } catch { XCTAssertEqual(error as? ClientError, .invalidInput) }
        let after = await transport.recorded(); XCTAssertEqual(after.count, 4)
    }
    func testTagReactionsKeepExactFromContextAndSingleAttemptForms() async throws {
        let transport = ExploreHTTP([#"{"status":200}"#, #"{"status":200}"#, #"{"status":200}"#]), api = try api(transport)
        let source = try TagFeed(tag: "Cats", kind: .trending).source, epoch = await api.sessionEpoch()
        XCTAssertTrue(ViewerInteraction.allowsUnsmile(source: source))
        try await api.smile(postID: "TagPost", enabled: true, source: source, session: epoch)
        try await api.unsmile(postID: "TagPost", enabled: true, source: source, session: epoch)
        try await api.republish(postID: "TagPost", enabled: true, source: source, session: epoch)
        let requests = await transport.recorded()
        XCTAssertEqual(requests.map { $0.httpMethod }, ["PUT", "PUT", "POST"])
        for request in requests { XCTAssertEqual(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems, [URLQueryItem(name: "from", value: "trending:Cats")]) }
        do { try await api.smile(postID: "TagPost", enabled: true, source: "trending:", session: epoch); XCTFail("Empty tag source") } catch { XCTAssertEqual(error as? ClientError, .invalidInput) }
    }
    func testExploreResponseCannotCrossSelectedAccountEpoch() async throws {
        let transport = ExploreHTTP([tags], hold: true), api = try api(transport)
        let flight = Task { try await api.explore() }; await transport.waitUntilHeld()
        try await api.forgetSession(); await transport.finish()
        do { _ = try await flight.value; XCTFail("A late account response must be discarded") } catch { XCTAssertEqual(error as? ClientError, .sessionChanged) }
    }
}
