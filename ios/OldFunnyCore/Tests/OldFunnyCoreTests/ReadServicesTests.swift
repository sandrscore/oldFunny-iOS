import XCTest
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import OldFunnyCore

private final class ReadMemoryStore: ReadStateStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values = [String: SavedReadState](), failing = false
    func failNextSave() { lock.lock(); failing = true; lock.unlock() }
    func load(key: String) throws -> SavedReadState? { lock.lock(); defer { lock.unlock() }; return values[key] }
    func save(_ state: SavedReadState, key: String) throws {
        lock.lock(); defer { lock.unlock() }
        if failing { failing = false; throw ClientError.transport }; values[key] = state
    }
}
private actor ReadFixtureBackend: ReadBackend {
    private var selected: ReadContext
    var counter = 10, failures = 0
    private var pages = [PostPage](), events = [String](), batches = [[String]]()
    private var pageContextTransition: ReadContext?
    private var hold = false, held: CheckedContinuation<Void, Never>?, observed: CheckedContinuation<Void, Never>?
    init(_ context: ReadContext) { selected = context }
    func readContext() -> ReadContext { selected }
    func switchTo(_ context: ReadContext) { selected = context }
    func changeContextDuringPage(_ context: ReadContext) { pageContextTransition = context }
    func configure(counter: Int? = nil, failures: Int = 0, pages: [PostPage] = []) {
        if let counter { self.counter = counter }; self.failures = failures; self.pages = pages
    }
    func holdNext() { hold = true }
    func waitUntilHeld() async { if held == nil { await withCheckedContinuation { observed = $0 } } }
    func finish() { held?.resume(); held = nil }
    func recorded() -> ([String], [[String]]) { (events, batches) }
    func acknowledgeReads(_ ids: [String], feed: Feed, context: ReadContext) async throws {
        guard context == selected else { throw ClientError.sessionChanged }
        events.append("ack:" + feed.source); batches.append(ids)
        if hold { hold = false; await withCheckedContinuation { held = $0; observed?.resume(); observed = nil } }
        if failures > 0 { failures -= 1; throw ClientError.transport }
    }
    func unreadSubscriptions(context: ReadContext) async throws -> Int {
        guard context == selected else { throw ClientError.sessionChanged }; events.append("counter"); return counter
    }
    func clearSubscriptionReads(context: ReadContext) async throws {
        guard context == selected else { throw ClientError.sessionChanged }
        events.append("clear"); if failures > 0 { failures -= 1; throw ClientError.transport }
    }
    func readPage(_ feed: Feed, next: String?, context: ReadContext) async throws -> PostPage {
        guard context == selected else { throw ClientError.sessionChanged }; events.append("page:" + (next ?? "head"))
        guard !pages.isEmpty else { throw ClientError.transport }
        if let replacement = pageContextTransition { selected = replacement; pageContextTransition = nil }
        return pages.removeFirst()
    }
}
private struct ReadCredentialStore: CredentialStore {
    var signedIn = true
    func read() throws -> Credential? { signedIn ? try Credential(accessToken: "read-fixture", refreshToken: nil, accountID: "FixtureUser", nickname: "Fixture") : nil }
    func write(_ credential: Credential) throws {}
    func erase() throws {}
}
private actor ReadHTTPFixture: HTTPTransport {
    private var responses: [HTTPResult], requests = [URLRequest]()
    init(_ responses: [HTTPResult]) { self.responses = responses }
    func send(_ request: URLRequest) async throws -> HTTPResult {
        requests.append(request); guard !responses.isEmpty else { throw ClientError.transport }; return responses.removeFirst()
    }
    func recorded() -> [URLRequest] { requests }
}
final class ReadServicesTests: XCTestCase {
    func testFailedFeaturedQueueDoesNotStarveSubscriptionAcknowledgmentsOrCounter() async throws {
        let backend = ReadFixtureBackend(context()), coordinator = ReadCoordinator(backend: backend, store: ReadMemoryStore())
        try await coordinator.refreshCounter()
        _ = try await coordinator.viewed("FeaturedPending", feed: .featured)
        _ = try await coordinator.viewed("SubscriptionPending", feed: .subscriptions)
        await backend.configure(failures: 1)
        do { _ = try await coordinator.flush(); XCTFail("Featured failure must remain retryable") }
        catch { XCTAssertEqual(error as? ClientError, .transport) }
        let state = try await coordinator.snapshot()
        XCTAssertEqual(state.featured.pending, ["FeaturedPending"])
        XCTAssertTrue(state.subscriptions.pending.isEmpty, "Independent Subscriptions worker must still make progress")
        XCTAssertEqual(state.progress.remaining, 9); XCTAssertFalse(state.counterDirty)
        let events = await backend.recorded(); XCTAssertEqual(Array(events.0.suffix(3)), ["ack:feat", "ack:subs", "counter"])
    }
    func testFeedRetryNeverCrossesAccountOrSignOutEpoch() async throws {
        for sameKey in [false, true] {
            let a = context(), changed = context(sameKey ? "a" : "b")
            let backend = ReadFixtureBackend(a), coordinator = ReadCoordinator(backend: backend, store: ReadMemoryStore())
            await backend.configure(pages: [try page(["OldAccountPost"], next: nil)])
            await backend.changeContextDuringPage(changed)
            do { _ = try await coordinator.scopedPage(.featured); XCTFail("Account/epoch changes must not retry") }
            catch { XCTAssertEqual(error as? ClientError, .sessionChanged) }
            let events = await backend.recorded(); XCTAssertEqual(events.0, ["page:head"])
            let state = try await coordinator.snapshot(); XCTAssertTrue(state.featured.seen.isEmpty)
        }
    }
    private func context(_ letter: String = "a", signed: Bool = true) -> ReadContext {
        ReadContext(key: String(repeating: letter, count: 40), epoch: UUID(), signedIn: signed, authorizationMarker: "transient")
    }
    private func page(_ ids: [String], next: String?) throws -> PostPage {
        PostPage(posts: try ids.map { try Post(.object(["id": .string($0), "type": .string("pic")])) }, paging: try Paging(next: next))
    }
    func testCapturedClearCannotApplyToAnotherSelectedAccount() async throws {
        let a = context(), b = context("b"), backend = ReadFixtureBackend(a)
        let coordinator = ReadCoordinator(backend: backend, store: ReadMemoryStore())
        _ = try await coordinator.currentSnapshot()
        await backend.switchTo(b)
        do { try await coordinator.clearSubscriptions(expected: a); XCTFail("Old confirmation must not clear B") }
        catch { XCTAssertEqual(error as? ClientError, .sessionChanged) }
        let events = await backend.recorded(); XCTAssertTrue(events.0.isEmpty)
        let state = try await coordinator.snapshot(); XCTAssertNil(state.progress.remaining)
    }
    func testDurableStatePersistsBoundedIDsSeparatelyAndRejectsTraversal() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FileReadStateStore(directory: root), a = context(), b = context("b")
        var state = SavedReadState(); state.featured = ReadLedger(savedSeen: "Seen", savedPending: "Pending")
        state.subscriptions = ReadLedger(savedSeen: "Subscribed", savedPending: "Subscribed")
        state.subscriptionsProgress = "10,2"; state.counterDirty = true
        try store.save(state, key: a.key)
        XCTAssertEqual(try store.load(key: a.key), state); XCTAssertNil(try store.load(key: b.key))
        let data = try Data(contentsOf: root.appendingPathComponent(a.key + ".json")), text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.contains("transient")); XCTAssertFalse(text.contains(a.epoch.uuidString)); XCTAssertFalse(text.contains("Bearer"))
        XCTAssertThrowsError(try store.save(state, key: "../outside"))
    }
    func testFailedAcknowledgmentAndRestartKeepImmediateLocalCreditUntilServerCatchesUp() async throws {
        let selected = context(), backend = ReadFixtureBackend(selected), store = ReadMemoryStore()
        var coordinator = ReadCoordinator(backend: backend, store: store)
        try await coordinator.refreshCounter()
        let new = try await coordinator.viewed("First", feed: .subscriptions, expected: selected); XCTAssertTrue(new)
        await backend.configure(failures: 1)
        do { _ = try await coordinator.flush(); XCTFail("Expected lost acknowledgement") } catch { XCTAssertEqual(error as? ClientError, .transport) }
        var state = try await coordinator.snapshot(); XCTAssertEqual(state.progress.remaining, 9); XCTAssertEqual(state.subscriptions.pending, ["First"])
        coordinator = ReadCoordinator(backend: backend, store: store)
        _ = try await coordinator.flush(); state = try await coordinator.snapshot()
        XCTAssertEqual(state.progress.remaining, 9); XCTAssertTrue(state.subscriptions.pending.isEmpty)
        await backend.configure(counter: 9); try await coordinator.refreshCounter(); state = try await coordinator.snapshot()
        XCTAssertEqual(state.progress.remaining, 9); XCTAssertEqual(state.progress.credit, 0)
        let duplicate = try await coordinator.viewed("First", feed: .subscriptions, expected: selected); XCTAssertFalse(duplicate)
    }
    func testPersistenceFailureCannotCreditOrQueueAnUnstoredRead() async throws {
        let backend = ReadFixtureBackend(context()), store = ReadMemoryStore(), coordinator = ReadCoordinator(backend: backend, store: store)
        store.failNextSave()
        do { _ = try await coordinator.viewed("NotStored", feed: .featured); XCTFail("Expected persistence failure") } catch { XCTAssertEqual(error as? ClientError, .transport) }
        let state = try await coordinator.snapshot(); XCTAssertTrue(state.featured.seen.isEmpty); XCTAssertTrue(state.featured.pending.isEmpty)
        let events = await backend.recorded(); XCTAssertTrue(events.0.isEmpty)
    }
    func testBoundedFlushJobsAndArrivalsDuringWriteDoNotLosePendingIDs() async throws {
        let selected = context(), backend = ReadFixtureBackend(selected), store = ReadMemoryStore(), coordinator = ReadCoordinator(backend: backend, store: store)
        for i in 0..<125 { _ = try await coordinator.viewed("Post\(i)", feed: .featured) }
        let more = try await coordinator.flush(); XCTAssertTrue(more)
        var state = try await coordinator.snapshot(); XCTAssertEqual(state.featured.pending.count, 5)
        _ = try await coordinator.flush()
        let recorded = await backend.recorded(); XCTAssertEqual(recorded.1.map(\.count), [30, 30, 30, 30, 5])
        _ = try await coordinator.viewed("During1", feed: .featured); await backend.holdNext()
        let flight = Task { try await coordinator.flush() }; await backend.waitUntilHeld()
        _ = try await coordinator.viewed("During2", feed: .featured); await backend.finish(); _ = try await flight.value
        state = try await coordinator.snapshot(); XCTAssertTrue(state.featured.pending.isEmpty)
        XCTAssertTrue(state.featured.seen.contains("During1")); XCTAssertTrue(state.featured.seen.contains("During2"))
    }
    func testLateAccountResponseAndCapturedOldViewerCannotAffectNewAccount() async throws {
        let a = context(), b = context("b"), backend = ReadFixtureBackend(a), store = ReadMemoryStore(), coordinator = ReadCoordinator(backend: backend, store: store)
        _ = try await coordinator.viewed("Old", feed: .featured, expected: a); await backend.holdNext()
        let flight = Task { try await coordinator.flush() }; await backend.waitUntilHeld(); await backend.switchTo(b)
        _ = try await coordinator.viewed("New", feed: .subscriptions, expected: b)
        do { _ = try await coordinator.viewed("Wrong", feed: .subscriptions, expected: a); XCTFail("Late viewer must be rejected") } catch { XCTAssertEqual(error as? ClientError, .sessionChanged) }
        await backend.finish()
        do { _ = try await flight.value; XCTFail("Late receipt must be rejected") } catch { XCTAssertEqual(error as? ClientError, .sessionChanged) }
        let state = try await coordinator.snapshot(); XCTAssertEqual(state.subscriptions.pending, ["New"]); XCTAssertTrue(state.featured.seen.isEmpty)
        XCTAssertEqual(try store.load(key: a.key)?.featured.pending, ["Old"])
    }
    func testFeaturedFlushPrecedesGETAndFiltersViewedPagesWithoutReorderingOrCursorLoops() async throws {
        let backend = ReadFixtureBackend(context()), coordinator = ReadCoordinator(backend: backend, store: ReadMemoryStore())
        _ = try await coordinator.viewed("Seen", feed: .featured)
        await backend.configure(pages: [try page(["Seen"], next: "next"), try page(["New2", "Seen", "New1"], next: "next")])
        let result = try await coordinator.page(.featured)
        XCTAssertEqual(result.posts.map(\.id), ["New2", "New1"]); XCTAssertNil(result.paging.next)
        let events = await backend.recorded(); XCTAssertEqual(events.0, ["ack:feat", "page:head", "page:next"])
    }
    func testExplicitClearRequiresSuccessAndPreservesViewedAndPendingHistory() async throws {
        let backend = ReadFixtureBackend(context()), coordinator = ReadCoordinator(backend: backend, store: ReadMemoryStore())
        try await coordinator.refreshCounter(); _ = try await coordinator.viewed("Sub", feed: .subscriptions)
        await backend.configure(failures: 1)
        do { try await coordinator.clearSubscriptions(); XCTFail("Expected uncertain clear") } catch { XCTAssertEqual(error as? ClientError, .transport) }
        var state = try await coordinator.snapshot(); XCTAssertEqual(state.progress.remaining, 9)
        try await coordinator.clearSubscriptions(); state = try await coordinator.snapshot()
        XCTAssertEqual(state.progress.remaining, 0); XCTAssertEqual(state.subscriptions.pending, ["Sub"]); XCTAssertEqual(state.subscriptions.seen, ["Sub"])
    }
    func testReadEndpointsUseCapturedSessionAnonymousFeaturedAndStrictCounters() async throws {
        let replies = [HTTPResult(status: 204, body: Data()), HTTPResult(status: 200, body: Data(#"{"status":200,"data":{"subscriptions":"12"}}"#.utf8)), HTTPResult(status: 204, body: Data())]
        let transport = ReadHTTPFixture(replies)
        let api = try APIClient(installation: String(repeating: "a", count: 64), userAgent: "fixture", store: ReadCredentialStore(), transport: transport)
        let selected = await api.readContext()
        try await api.acknowledgeReads(["One", "Two"], feed: .subscriptions, context: selected)
        let count = try await api.unreadSubscriptions(context: selected); XCTAssertEqual(count, 12)
        try await api.clearSubscriptionReads(context: selected)
        let requests = await transport.recorded()
        XCTAssertEqual(requests.map { $0.httpMethod }, ["PUT", "GET", "PUT"])
        XCTAssertEqual(requests.map { $0.url!.path }, ["/v4/reads/One,Two", "/v4/counters", "/v4/reads/all"])
        XCTAssertEqual(requests[0].url?.query, "from=subs"); XCTAssertEqual(requests[2].url?.query, "from=subs")
        try await api.forgetSession()
        do { try await api.acknowledgeReads(["Wrong"], feed: .featured, context: selected); XCTFail("Old session cannot write") } catch { XCTAssertEqual(error as? ClientError, .sessionChanged) }
        let anonymousTransport = ReadHTTPFixture([HTTPResult(status: 204, body: Data())])
        let anonymous = try APIClient(installation: String(repeating: "b", count: 64), userAgent: "fixture", store: ReadCredentialStore(signedIn: false), transport: anonymousTransport)
        try await anonymous.acknowledgeReads(["Public"], feed: .featured, context: anonymous.readContext())
        let publicRequests = await anonymousTransport.recorded()
        XCTAssertTrue(publicRequests[0].value(forHTTPHeaderField: "Authorization")?.hasPrefix("Basic ") == true)
        XCTAssertEqual(publicRequests[0].url?.query, "from=feat")
    }
    func testMissingNegativeFractionalAndNoncanonicalCounterValuesNeverBecomeZero() async throws {
        for value in ["null", "-1", "1.5", "true", "\"01\"", "\"-1\"", "\"1.0\"", "2147483648"] {
            let transport = ReadHTTPFixture([HTTPResult(status: 200, body: Data(("{\"status\":200,\"data\":{\"subscriptions\":" + value + "}}").utf8))])
            let api = try APIClient(installation: String(repeating: "a", count: 64), userAgent: "fixture", store: ReadCredentialStore(), transport: transport)
            do { _ = try await api.unreadSubscriptions(context: api.readContext()); XCTFail("Invalid counter \(value)") }
            catch { XCTAssertEqual(error as? ClientError, .malformedResponse) }
        }
    }
}
