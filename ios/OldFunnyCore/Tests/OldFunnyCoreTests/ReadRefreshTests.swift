import XCTest
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import OldFunnyCore

private final class RefreshReadStore: CredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var credential = try! Credential(accessToken: "expired-fixture", refreshToken: "refresh-fixture", accountID: "Fixture", nickname: "Fixture")
    func read() throws -> Credential? { lock.lock(); defer { lock.unlock() }; return credential }
    func write(_ credential: Credential) throws { lock.lock(); defer { lock.unlock() }; self.credential = credential }
    func erase() throws {}
}
private struct RefreshReadHistory: ReadStateStore {
    func load(key: String) throws -> SavedReadState? { nil }
    func save(_ state: SavedReadState, key: String) throws {}
}
private actor RefreshReadTransport: HTTPTransport {
    private var first = true, requests = [URLRequest]()
    func send(_ request: URLRequest) async throws -> HTTPResult {
        requests.append(request)
        if request.url!.path == "/v4/oauth2/token" {
            return HTTPResult(status: 200, body: Data(#"{"access_token":"fresh-fixture","refresh_token":"refresh-fixture"}"#.utf8))
        }
        guard request.httpMethod == "GET", request.url!.path == "/v4/feeds/featured" else { throw ClientError.invalidInput }
        if first { first = false; return HTTPResult(status: 401, body: Data()) }
        return HTTPResult(status: 200, body: Data(#"{"status":200,"data":{"content":{"items":[{"id":"Fresh","type":"picture"}],"paging":{"hasNext":false}}}}"#.utf8))
    }
    func recorded() -> [URLRequest] { requests }
}
final class ReadRefreshTests: XCTestCase {
    func testFeedSurvivesExistingReadOnlyTokenRefreshWithoutChangingAccountOrReplayingWrites() async throws {
        let transport = RefreshReadTransport()
        let api = try APIClient(installation: String(repeating: "a", count: 64), userAgent: "offline refresh regression", store: RefreshReadStore(), transport: transport)
        let before = await api.readContext()
        let coordinator = ReadCoordinator(backend: api, store: RefreshReadHistory())
        let page = try await coordinator.page(.featured)
        XCTAssertEqual(page.posts.map(\.id), ["Fresh"])
        let after = await api.readContext()
        XCTAssertEqual(before.key, after.key); XCTAssertEqual(before.epoch, after.epoch)
        XCTAssertNotEqual(before.authorizationMarker, after.authorizationMarker)
        let requests = await transport.recorded()
        XCTAssertEqual(requests.filter { $0.httpMethod != "GET" }.map { $0.url!.path }, ["/v4/oauth2/token"])
        XCTAssertLessThanOrEqual(requests.filter { $0.httpMethod == "GET" }.count, 3)
    }
}
