import XCTest
@testable import OldFunnyCore
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private final class MemoryStore: CredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var value: Credential?
    init(_ value: Credential? = nil) { self.value = value }
    func read() throws -> Credential? { lock.lock(); defer { lock.unlock() }; return value }
    func write(_ value: Credential) throws { lock.lock(); defer { lock.unlock() }; self.value = value }
    func erase() throws { lock.lock(); defer { lock.unlock() }; value = nil }
}

private actor ScriptedTransport: HTTPTransport {
    var replies: [HTTPResult]
    var requests: [URLRequest] = []
    init(_ replies: [HTTPResult]) { self.replies = replies }
    func send(_ request: URLRequest) async throws -> HTTPResult {
        requests.append(request)
        guard !replies.isEmpty else { throw ClientError.transport }
        return replies.removeFirst()
    }
    func recorded() -> [URLRequest] { requests }
}

private func reply(_ json: String, status: Int = 200) -> HTTPResult { HTTPResult(status: status, body: Data(json.utf8)) }
private let emptyPage = #"{"status":200,"data":{"content":{"items":[],"paging":{"hasNext":false}}}}"#
private let installation = String(repeating: "a", count: 64)
private func token(_ name: String = "fixtureAccess", refresh: String? = "fixtureRefresh") throws -> Credential {
    try Credential(accessToken: name, refreshToken: refresh, accountID: "FixtureUser", nickname: "Fixture")
}

final class CoreTests: XCTestCase {
    func testModernProtocolProfileIsUsedOnActualRequests() async throws {
        let agent = Wire.apiUserAgent(systemVersion: "27.0.1", model: "iPhone")
        XCTAssertEqual(agent, "iFunny/10.45.1(25370) iPhone/27.0.1 (Apple; iPhone)")
        let transport = ScriptedTransport([reply(emptyPage), reply("{}"), reply("{}", status: 403)])
        let client = try APIClient(installation: installation, userAgent: agent, store: MemoryStore(), transport: transport)
        _ = try await client.feed(.featured)
        do { try await client.signIn(username: "fixture", password: "fixture"); XCTFail("Expected fixture rejection") }
        catch { XCTAssertEqual(error as? ClientError, .http(403)) }
        let requests = await transport.recorded()
        XCTAssertEqual(requests.map { $0.url!.path }, ["/v4/feeds/featured", "/v4/app/features", "/v4/oauth2/token"])
        XCTAssertTrue(requests.allSatisfy { $0.value(forHTTPHeaderField: "User-Agent") == agent })
    }
    func testNetworkErrorsKeepOnlySafeNumericCodes() {
        let error = URLError(.networkConnectionLost, userInfo: [NSURLErrorFailingURLStringErrorKey: "https://private.invalid/?token=fixture-secret", NSLocalizedDescriptionKey: "fixture-private-description"])
        let sanitized = ClientError.networkFailure(error)
        XCTAssertEqual(sanitized, .network(-1005))
        XCTAssertTrue(sanitized.localizedDescription.contains("server connection was closed"))
        XCTAssertTrue(sanitized.localizedDescription.contains("-1005"))
        XCTAssertFalse(sanitized.localizedDescription.contains("private"))
        XCTAssertFalse(sanitized.localizedDescription.contains("secret"))
        XCTAssertEqual(ClientError.networkFailure(NSError(domain: "private-domain", code: 1)), .transport)
        XCTAssertTrue(ClientError.network(URLError.notConnectedToInternet.rawValue).localizedDescription.contains("offline"))
    }
    func testSHA1AndPublicBasicProtocol() throws {
        XCTAssertEqual(SHA1.hex(Data()), "da39a3ee5e6b4b0d3255bfef95601890afd80709")
        XCTAssertEqual(SHA1.hex(Data("abc".utf8)), "a9993e364706816aba3e25717850c26c9cd0d89d")
        XCTAssertEqual(SHA1.hex(Data(String(repeating: "a", count: 1_000_000).utf8)), "34aa973cd4c4daa4f61eeb2bdbad27316534016f")
        // Independent hashlib-generated expected protocol vector.
        XCTAssertEqual(try Wire.basic(installation: installation),
                       "Basic YWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYV9KdWlVSCYzODIyOmE0YzExYzJjY2EzNDMyNmExNzhmM2U2OWU5ZTVjMzUwZmVhM2U1NDg=")
        XCTAssertThrowsError(try Wire.basic(installation: "not-an-installation"))
    }
    func testPasswordFormPreservesUnicodeAndReservedCharacters() throws {
        let data = Wire.form([("grant_type", "password"), ("username", "a+b@example.invalid"), ("password", "&= 🔒\n")])
        XCTAssertEqual(String(decoding: data, as: UTF8.self),
                       "grant_type=password&username=a%2Bb%40example.invalid&password=%26%3D+%F0%9F%94%92%0A")
    }
    func testCaptchaOriginValidation() throws {
        func url(_ text: String) throws -> URL? {
            Wire.captcha(try JSON.decode(Data("{\"error\":\"captcha_required\",\"data\":{\"captcha_url\":\"\(text)\"}}".utf8)))
        }
        XCTAssertNotNil(try url("https://ifunny.co/captcha/fixture"))
        for bad in ["http://ifunny.co/captcha/x", "https://ifunny.co.attacker.invalid/captcha/x", "https://ifunny.co@attacker.invalid/captcha/x", "https://ifunny.co:443/captcha/x", "https://ifunny.co/elsewhere"] {
            XCTAssertNil(try url(bad))
        }
    }
    func testCaptchaCallbackRequiresExactSignalFromTrustedMainPage() throws {
        let challenge = URL(string: "https://ifunny.co/captcha/fixture-only")!
        let resolved = URL(string: "ifunny://captcha_resolved")!
        func decision(_ destination: URL, _ source: URL? = nil, _ sourceMain: Bool = true, _ targetMain: Bool = true) -> CaptchaPolicy.Decision {
            CaptchaPolicy.decide(destination: destination, source: source, sourceIsMainFrame: sourceMain, targetIsMainFrame: targetMain)
        }
        XCTAssertEqual(decision(resolved, challenge), .resolved)
        XCTAssertEqual(decision(resolved), .block)
        XCTAssertEqual(decision(resolved, challenge, false), .block)
        XCTAssertEqual(decision(resolved, challenge, true, false), .block)
        for source in ["https://ifunny.co.attacker.invalid/captcha/a", "http://ifunny.co/captcha/a", "https://ifunny.co/other", "https://google.com/recaptcha", "https://ifunny.co:443/captcha/a"] {
            XCTAssertEqual(decision(resolved, URL(string: source)), .block)
        }
        for destination in ["ifunny://captcha_resolved?accepted=1", "ifunny://captcha_resolved#fake", "ifunny://captcha_resolved.attacker", "ifunny://other", "https://ifunny.co/", "http://ifunny.co/captcha/a", "https://attacker.invalid/captcha/a", "javascript:alert(1)"] {
            XCTAssertEqual(decision(URL(string: destination)!, challenge), .block)
        }
        XCTAssertEqual(decision(challenge), .allowPage)
        XCTAssertEqual(decision(URL(string: "https://www.google.com/recaptcha/api2/anchor")!, challenge, true, false), .allowPage)
        XCTAssertEqual(decision(URL(string: "about:blank")!, challenge, false, false), .allowPage)
        XCTAssertEqual(decision(URL(string: "about:blank")!, challenge), .block)
    }
    func testCaptchaRetryUsesSameInstallationAndCommitsOnlyAfterServerAccepts() async throws {
        let old = try token()
        let store = MemoryStore(old)
        let challenge = "https://ifunny.co/captcha/fixture-only"
        let transport = ScriptedTransport([
            reply("{}"), reply("{\"error\":\"captcha_required\",\"data\":{\"captcha_url\":\"\(challenge)\"}}", status: 403),
            reply("{}"), reply(#"{"access_token":"verifiedFixture","refresh_token":"verifiedRefresh"}"#),
            reply(#"{"data":{"user":{"id":"VerifiedUser","nick":"Verified"}}}"#)
        ])
        let client = try APIClient(installation: installation, userAgent: "Fixture", store: store, transport: transport)
        do { try await client.signIn(username: "fixture", password: "fixture&password"); XCTFail("Expected CAPTCHA") }
        catch { XCTAssertEqual(error as? ClientError, .captcha(URL(string: challenge)!)) }
        XCTAssertEqual(try store.read(), old)
        try await client.signIn(username: "fixture", password: "fixture&password")
        XCTAssertEqual(try store.read()?.accountID, "VerifiedUser")
        let requests = await transport.recorded()
        XCTAssertEqual(requests.map { $0.url!.path }, ["/v4/app/features", "/v4/oauth2/token", "/v4/app/features", "/v4/oauth2/token", "/v4/account"])
        XCTAssertTrue(requests.allSatisfy { $0.value(forHTTPHeaderField: "Cookie") == "device_id=" + installation })
        XCTAssertEqual(requests[1].httpBody, requests[3].httpBody)
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "Authorization"), requests[3].value(forHTTPHeaderField: "Authorization"))
    }
    func testFeedKeepsTextVideoAndSkipsDeletedAndDuplicateEntries() throws {
        let data = try JSON.decode(Data(#"{"content":{"items":[{"id":"Video1","type":"text_video","title":"Title","description":"Body","url":"https://media.invalid/a.mp4","video_clip":{"screen_url":"https://media.invalid/a.webp"},"size":{"w":640,"h":450}},{"id":"Video1"},{"id":"Deleted1","state":"deleted"},{"id":"Picture2","type":"picture","url":"file:///private/example"}],"paging":{"hasNext":true,"cursors":{"next":"opaque&+cursor"}}}}"#.utf8))
        let page = try PostPage(data)
        XCTAssertEqual(page.posts.map(\.id), ["Video1", "Picture2"])
        XCTAssertTrue(page.posts[0].isVideo)
        XCTAssertEqual(page.posts[0].title, "Title")
        XCTAssertEqual(page.posts[0].body, "Body")
        XCTAssertNotNil(page.posts[0].posterURL)
        XCTAssertNil(page.posts[1].mediaURL)
        XCTAssertEqual(page.paging.next, "opaque&+cursor")
        var pages = FeedPages()
        pages.apply(page, replacing: true)
        pages.apply(page, replacing: false)
        XCTAssertEqual(pages.posts.count, 2)
        XCTAssertNil(pages.next, "Repeated server cursor must end continuation")
        XCTAssertThrowsError(try PostPage(.object([:])))
    }
    func testCommentAttachmentRemainsUsableWithoutOriginalURL() throws {
        let value = try JSON.decode(Data(#"{"id":"Comment1","text":"","creator":{"nick":"Fixture"},"attachments":{"content":[{"id":"Picture1","type":"pic","thumb":{"proportional_url":"https://media.invalid/a.jpg"}}]}}"#.utf8))
        let comment = try Comment(value)
        XCTAssertEqual(comment.attachments.count, 1)
        XCTAssertNotNil(comment.attachments[0].posterURL)
        XCTAssertEqual(comment.author, "Fixture")
    }
    func testSignInCommitsOnlyAfterAccountLookupAndDoesNotStorePassword() async throws {
        let transport = ScriptedTransport([
            reply(#"{"status":200,"data":{}}"#),
            reply(#"{"access_token":"fixtureAccess","refresh_token":"fixtureRefresh"}"#),
            reply(#"{"status":200,"data":{"user":{"id":"FixtureUser","nick":"Fixture"}}}"#)
        ])
        let store = MemoryStore()
        let client = try APIClient(installation: installation, userAgent: "FixtureAgent", store: store, transport: transport)
        try await client.signIn(username: "fixture@example.invalid", password: "fixture-only&password")
        XCTAssertEqual(try store.read()?.accountID, "FixtureUser")
        let encoded = try JSONEncoder().encode(XCTUnwrap(store.read()))
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("password"))
        let requests = await transport.recorded()
        XCTAssertEqual(requests.map { $0.url!.path }, ["/v4/app/features", "/v4/oauth2/token", "/v4/account"])
        XCTAssertEqual(requests[1].httpMethod, "POST")
        XCTAssertFalse(String(decoding: requests[1].httpBody!, as: UTF8.self).contains("client_id"))
        XCTAssertEqual(requests[2].value(forHTTPHeaderField: "Authorization"), "Bearer fixtureAccess")
    }
    func testFailedSignInPreservesExistingSession() async throws {
        let old = try token()
        let store = MemoryStore(old)
        let transport = ScriptedTransport([reply("{}"), reply(#"{"access_token":"newFixtureAccess"}"#), reply("{}", status: 503)])
        let client = try APIClient(installation: installation, userAgent: "Fixture", store: store, transport: transport)
        do { try await client.signIn(username: "fixture", password: "fixture"); XCTFail("Expected failure") }
        catch { XCTAssertEqual(error as? ClientError, .http(503)) }
        XCTAssertEqual(try store.read(), old)
    }
    func testGETRefreshRetriesOnceAndPersistsRotation() async throws {
        let transport = ScriptedTransport([
            reply("{}", status: 401), reply(#"{"access_token":"rotatedAccess","refresh_token":"rotatedRefresh"}"#), reply(emptyPage)
        ])
        let store = MemoryStore(try token())
        let client = try APIClient(installation: installation, userAgent: "Fixture", store: store, transport: transport)
        _ = try await client.feed(.featured, next: "opaque&+cursor")
        let requests = await transport.recorded()
        XCTAssertEqual(requests.count, 3)
        XCTAssertEqual(requests[1].url?.path, "/v4/oauth2/token")
        XCTAssertEqual(requests[2].value(forHTTPHeaderField: "Authorization"), "Bearer rotatedAccess")
        XCTAssertEqual(URLComponents(url: requests[2].url!, resolvingAgainstBaseURL: false)?.queryItems?.last?.value, "opaque&+cursor")
        XCTAssertEqual(try store.read()?.refreshToken, "rotatedRefresh")
    }
    func testWritesNeverReplayAfterUnauthorizedOrUncertainResponse() async throws {
        let transport = ScriptedTransport([reply("{}", status: 401)])
        let client = try APIClient(installation: installation, userAgent: "Fixture", store: MemoryStore(try token()), transport: transport)
        do { try await client.sendComment(postID: "Post1", text: "fixture"); XCTFail("Expected failure") }
        catch { XCTAssertEqual(error as? ClientError, .http(401)) }
        let requests = await transport.recorded()
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].httpMethod, "POST")
    }
    func testInvalidIDsAndUnsignedWritesNeverReachTransport() async throws {
        let transport = ScriptedTransport([])
        let client = try APIClient(installation: installation, userAgent: "Fixture", store: MemoryStore(), transport: transport)
        do { _ = try await client.comments(postID: "../account"); XCTFail("Expected failure") }
        catch { XCTAssertEqual(error as? ClientError, .invalidInput) }
        do { try await client.smile(postID: "Post1", enabled: true, source: "feat"); XCTFail("Expected failure") }
        catch { XCTAssertEqual(error as? ClientError, .signInRequired) }
        let requests = await transport.recorded()
        XCTAssertTrue(requests.isEmpty)
    }
    func testRawErrorBodiesAreNotExposed() async throws {
        let transport = ScriptedTransport([reply(#"{"error":"fixture-private-content"}"#, status: 500)])
        let client = try APIClient(installation: installation, userAgent: "Fixture", store: MemoryStore(), transport: transport)
        do { _ = try await client.feed(.featured); XCTFail("Expected failure") }
        catch { XCTAssertFalse(error.localizedDescription.contains("fixture-private-content")) }
    }
}

private actor DelayedTransport: HTTPTransport {
    var continuation: CheckedContinuation<HTTPResult, Never>?
    var started: CheckedContinuation<Void, Never>?
    var entered = false
    func send(_ request: URLRequest) async throws -> HTTPResult {
        entered = true; started?.resume(); started = nil
        return await withCheckedContinuation { continuation = $0 }
    }
    func waitUntilStarted() async {
        if !entered { await withCheckedContinuation { started = $0 } }
    }
    func release() { continuation?.resume(returning: reply(emptyPage)); continuation = nil }
}

private actor RefreshTransport: HTTPTransport {
    var expiredRequests = 0
    var refreshRequests = 0
    var refreshWaiter: CheckedContinuation<HTTPResult, Never>?
    func send(_ request: URLRequest) async throws -> HTTPResult {
        if request.url?.path == "/v4/oauth2/token" {
            refreshRequests += 1
            if expiredRequests < 2 { return await withCheckedContinuation { refreshWaiter = $0 } }
            return reply(#"{"access_token":"rotatedAccess"}"#)
        }
        if request.value(forHTTPHeaderField: "Authorization") == "Bearer fixtureAccess" {
            expiredRequests += 1
            if expiredRequests == 2 {
                refreshWaiter?.resume(returning: reply(#"{"access_token":"rotatedAccess"}"#)); refreshWaiter = nil
            }
            return reply("{}", status: 401)
        }
        return reply(emptyPage)
    }
    func count() -> Int { refreshRequests }
}

extension CoreTests {
    func testConcurrentUnauthorizedReadsShareOneRefresh() async throws {
        let transport = RefreshTransport()
        let client = try APIClient(installation: installation, userAgent: "Fixture", store: MemoryStore(try token()), transport: transport)
        async let first = client.feed(.featured)
        async let second = client.feed(.featured)
        _ = try await (first, second)
        let count = await transport.count()
        XCTAssertEqual(count, 1)
    }
    func testResponseFromForgottenSessionIsDiscarded() async throws {
        let transport = DelayedTransport()
        let client = try APIClient(installation: installation, userAgent: "Fixture", store: MemoryStore(try token()), transport: transport)
        let pending = Task { try await client.feed(.featured) }
        await transport.waitUntilStarted()
        try await client.forgetSession()
        await transport.release()
        do { _ = try await pending.value; XCTFail("Stale response must be rejected") }
        catch { XCTAssertEqual(error as? ClientError, .sessionChanged) }
    }
}
