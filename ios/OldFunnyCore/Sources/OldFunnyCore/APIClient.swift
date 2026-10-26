import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct Credential: Codable, Equatable, Sendable {
    public let accessToken: String
    public let refreshToken: String?
    public let accountID: String
    public let nickname: String
    public init(accessToken: String, refreshToken: String?, accountID: String, nickname: String) throws {
        guard !accessToken.isEmpty, accessToken.utf8.count <= 16384,
              !accessToken.contains(where: \.isWhitespace), Wire.validID(accountID),
              refreshToken == nil || (!(refreshToken!.isEmpty) && refreshToken!.utf8.count <= 16384 && !refreshToken!.contains(where: \.isWhitespace)) else {
            throw ClientError.malformedResponse
        }
        self.accessToken = accessToken; self.refreshToken = refreshToken
        self.accountID = accountID; self.nickname = nickname
    }
}

public protocol CredentialStore: Sendable {
    func read() throws -> Credential?
    func write(_ credential: Credential) throws
    func erase() throws
}

public struct HTTPResult: Sendable {
    public let status: Int
    public let body: Data
    public init(status: Int, body: Data) { self.status = status; self.body = body }
}
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> HTTPResult
}

/// Authenticated redirects are refused, cookies are explicit, and TLS uses the
/// platform's normal certificate validation. No credential/header/body logging.
public final class URLTransport: NSObject, HTTPTransport, URLSessionTaskDelegate, @unchecked Sendable {
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 25
        configuration.timeoutIntervalForResource = 45
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()
    // Initializing lazy session before sharing avoids concurrent initialization.
    public override init() { super.init(); _ = session }
    public func send(_ request: URLRequest) async throws -> HTTPResult {
        do {
            let (body, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, body.count <= 8 * 1024 * 1024 else { throw ClientError.malformedResponse }
            return HTTPResult(status: http.statusCode, body: body)
        } catch is CancellationError { throw CancellationError() }
        catch let error as ClientError { throw error }
        catch let error as URLError where error.code == .cancelled { throw CancellationError() }
        catch { throw ClientError.networkFailure(error) }
    }
    public func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                           newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

public actor APIClient {
    public let installation: String
    private let transport: any HTTPTransport
    private let publicPictureTransport: any HTTPTransport
    private let store: any CredentialStore
    private let userAgent: String
    private var credential: Credential?
    private var epoch = UUID()
    private var refreshFlight: (owner: UUID, task: Task<Credential, Error>)?

    public init(installation: String, userAgent: String, store: any CredentialStore,
                transport: any HTTPTransport = URLTransport(), publicPictureTransport: any HTTPTransport = PublicPictureTransport()) throws {
        _ = try Wire.basic(installation: installation)
        self.installation = installation; self.userAgent = userAgent
        self.store = store; self.transport = transport
        self.publicPictureTransport = publicPictureTransport
        if let saved = try store.read() {
            credential = try Credential(accessToken: saved.accessToken, refreshToken: saved.refreshToken,
                                        accountID: saved.accountID, nickname: saved.nickname)
        }
    }
    public func account() -> Credential? { credential }
    public func sessionEpoch() -> UUID { epoch }

    public func forgetSession() throws {
        try store.erase()
        epoch = UUID(); credential = nil
        refreshFlight?.task.cancel(); refreshFlight = nil
    }

    private func request(path: String, query: [(String, String)] = [], method: String = "GET",
                         fields: [(String, String)]? = nil, token: String? = nil) throws -> URLRequest {
        guard !path.hasPrefix("/"), !path.contains(".."), !path.contains(":"), !path.contains("?"), !path.contains("#") else {
            throw ClientError.invalidInput
        }
        var components = URLComponents(url: Wire.base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = query.isEmpty ? nil : query.map { URLQueryItem(name: $0.0, value: $0.1) }
        guard let url = components.url, url.host == Wire.base.host else { throw ClientError.invalidInput }
        var request = URLRequest(url: url)
        request.httpMethod = method
        let authorization = try token.map { "Bearer " + $0 } ?? Wire.basic(installation: installation)
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("iFunny", forHTTPHeaderField: "iFunny-Project-Id")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("en-US", forHTTPHeaderField: "Accept-Language")
        request.setValue("1", forHTTPHeaderField: "ApplicationState")
        request.setValue("device_id=" + installation, forHTTPHeaderField: "Cookie")
        if let fields {
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = Wire.form(fields)
        }
        return request
    }
    private static func parse(_ response: HTTPResult) throws -> JSON {
        let value = try? JSON.decode(response.body)
        if response.status == 403, let value, let url = Wire.captcha(value) { throw ClientError.captcha(url) }
        guard (200..<300).contains(response.status) else { throw ClientError.http(response.status) }
        if response.status == 204 || response.body.isEmpty { return .null }
        guard let value else { throw ClientError.malformedResponse }
        if let status = value["status"].integer, !(200..<300).contains(status) { throw ClientError.http(status) }
        return value
    }

    public func signIn(username: String, password: String) async throws {
        guard !username.isEmpty, !password.isEmpty, username.utf8.count <= 1024, password.utf8.count <= 4096 else {
            throw ClientError.invalidInput
        }
        // Invalidate old in-flight work immediately, while retaining the current
        // session until both OAuth and the account lookup succeed.
        epoch = UUID(); let owner = epoch
        refreshFlight?.task.cancel(); refreshFlight = nil
        let bootstrap = try await transport.send(request(path: "app/features"))
        guard owner == epoch else { throw ClientError.sessionChanged }
        _ = try Self.parse(bootstrap)
        let response = try await transport.send(request(path: "oauth2/token", method: "POST", fields: [
            ("grant_type", "password"), ("username", username), ("password", password)
        ]))
        guard owner == epoch else { throw ClientError.sessionChanged }
        let token = try Self.parse(response)
        guard let access = token["access_token"].string, !access.isEmpty, !access.contains(where: \.isWhitespace) else {
            throw ClientError.malformedResponse
        }
        let accountResponse = try await transport.send(request(path: "account", token: access))
        guard owner == epoch else { throw ClientError.sessionChanged }
        let data = try Self.parse(accountResponse)["data"]
        let user = data["user"] == .null ? data : data["user"]
        let saved = try Credential(accessToken: access, refreshToken: token["refresh_token"].string,
                                   accountID: user["id"].string ?? "", nickname: user["nick"].string ?? username)
        try store.write(saved); credential = saved
        epoch = UUID()
    }

    private func refresh(owner: UUID, old: Credential) async throws {
        guard owner == epoch else { throw ClientError.sessionChanged }
        if credential?.accessToken != old.accessToken { return }
        guard let refreshToken = old.refreshToken else { throw ClientError.signInRequired }
        let task: Task<Credential, Error>
        if let flight = refreshFlight, flight.owner == owner { task = flight.task }
        else {
            let transport = self.transport
            let request = try request(path: "oauth2/token", method: "POST", fields: [
                ("grant_type", "refresh_token"), ("refresh_token", refreshToken)
            ])
            task = Task {
                let value = try Self.parse(await transport.send(request))
                return try Credential(accessToken: value["access_token"].string ?? "",
                                      refreshToken: value["refresh_token"].string ?? refreshToken,
                                      accountID: old.accountID, nickname: old.nickname)
            }
            refreshFlight = (owner, task)
        }
        do {
            let updated = try await task.value
            guard owner == epoch else { throw ClientError.sessionChanged }
            if credential?.accessToken == old.accessToken { try store.write(updated); credential = updated }
            refreshFlight = nil
        } catch {
            if owner == epoch { refreshFlight = nil }
            throw error
        }
    }

    private func call(path: String, query: [(String, String)] = [], method: String = "GET",
                      fields: [(String, String)]? = nil, authenticated: Bool = false) async throws -> JSON {
        let owner = epoch
        let response = try await rawResponse(path: path, query: query, method: method, fields: fields, authenticated: authenticated)
        guard owner == epoch else { throw ClientError.sessionChanged }
        return try Self.parse(response)
    }
    private func rawResponse(path: String, query: [(String, String)] = [], method: String = "GET",
                             fields: [(String, String)]? = nil, authenticated: Bool = false) async throws -> HTTPResult {
        let owner = epoch, selected = credential
        if authenticated && selected == nil { throw ClientError.signInRequired }
        var response = try await transport.send(request(path: path, query: query, method: method, fields: fields, token: selected?.accessToken))
        guard owner == epoch else { throw ClientError.sessionChanged }
        // Retry read-only requests once after refresh. Social writes are never replayed.
        if response.status == 401, method == "GET", let selected {
            try await refresh(owner: owner, old: selected)
            guard owner == epoch else { throw ClientError.sessionChanged }
            response = try await transport.send(request(path: path, query: query, token: credential?.accessToken))
            guard owner == epoch else { throw ClientError.sessionChanged }
        }
        return response
    }

    public func feed(_ feed: Feed, next: String? = nil) async throws -> PostPage {
        if let next, next.utf8.count > 8192 { throw ClientError.invalidInput }
        var query = [("limit", "30")]
        if let next { query.append(("next", next)) }
        // The supplied Android client uses POST form fields for this read.
        if feed == .collective {
            return try PostPage(await call(path: feed.path, method: "POST", fields: query)["data"])
        }
        return try PostPage(await call(path: feed.path, query: query, authenticated: feed == .subscriptions)["data"])
    }
    public func timeline(userID: String, next: String? = nil) async throws -> PostPage {
        var query = [("limit", "30")]
        if let next, next.utf8.count <= 8192 { query.append(("next", next)) }
        return try PostPage(await call(path: "timelines/users/" + Wire.requireID(userID), query: query)["data"])
    }
    public func content(postID: String) async throws -> Post {
        let id = try Wire.requireID(postID), owner = epoch
        let response = try await rawResponse(path: "content/" + id)
        guard owner == epoch else { throw ClientError.sessionChanged }
        if response.status != 404 {
            let post = try Post(Self.parse(response)["data"])
            guard post.id == id else { throw ClientError.malformedResponse }; return post
        } else {
            // The Android PublicPictures patch recovers only this exact error
            // for bounded public-picture IDs, never permission/auth failures.
            guard id.utf8.count <= 40 else { throw ClientError.http(404) }
            var request = URLRequest(url: URL(string: "https://ifunny.co/picture/" + id)!)
            request.httpMethod = "GET"; request.timeoutInterval = 8
            request.setValue("Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
            request.setValue("text/html", forHTTPHeaderField: "Accept")
            let response: HTTPResult
            do { response = try await publicPictureTransport.send(request) }
            catch is CancellationError { throw CancellationError() }
            catch { guard owner == epoch else { throw ClientError.sessionChanged }; throw ClientError.http(404) }
            guard owner == epoch else { throw ClientError.sessionChanged }
            guard response.status == 200, let post = try PublicPicture.parse(response.body, id: id) else { throw ClientError.http(404) }
            return post
        }
    }
    public func comments(postID: String, parentID: String? = nil, next: String? = nil) async throws -> CommentPage {
        var path = "content/" + (try Wire.requireID(postID)) + "/comments"
        if let parentID { path += "/" + (try Wire.requireID(parentID)) + "/replies" }
        var query = [("limit", String(CommentBehavior.pageSize))]
        if let next, next.utf8.count <= 8192 { query.append(("next", next)) }
        return try CommentPage(await call(path: path, query: query)["data"], replies: parentID != nil)
    }
    private func validateWriteSession(_ session: UUID?) throws {
        if let session, session != epoch { throw ClientError.sessionChanged }
    }
    public func sendComment(postID: String, parentID: String? = nil, text: String, attachmentID: String? = nil, mentions: [MentionSpan] = [], session: UUID? = nil) async throws {
        try validateWriteSession(session)
        let submitted = MentionDocument.asciiTrim(text)
        guard text.utf16.count <= 300, !submitted.isEmpty || attachmentID != nil else {
            throw ClientError.invalidInput
        }
        var path = "content/" + (try Wire.requireID(postID)) + "/comments"
        if let parentID { path += "/" + (try Wire.requireID(parentID)) + "/replies" }
        var fields = [("text", submitted)]
        if let attachmentID { fields.append(("content", try Wire.requireID(attachmentID))) }
        if let wire = MentionDocument(text: text, mentions: mentions).wire(for: submitted) { fields.append(("user_mentions", wire)) }
        _ = try await call(path: path, method: "POST", fields: fields, authenticated: true)
    }
    public func mentionUsers(query: String = "", next: String? = nil) async throws -> MentionUserPage {
        guard query.utf16.count <= 25, query.isEmpty || query.unicodeScalars.count >= 2,
              next == nil || next!.utf8.count <= 8192 else { throw ClientError.invalidInput }
        var fields = [("limit", query.isEmpty ? "9" : "20")]
        if !query.isEmpty { fields.append(("q", query)) }; if let next { fields.append(("next", next)) }
        return try MentionUserPage(await call(path: query.isEmpty ? "users/my/mention_users" : "search/users_for_mentions", query: fields, authenticated: true)["data"])
    }
    public func smile(postID: String, enabled: Bool, source: String, session: UUID? = nil) async throws {
        try validateWriteSession(session)
        guard ["feat", "coll", "subs", "prof"].contains(source) else { throw ClientError.invalidInput }
        _ = try await call(path: "content/" + Wire.requireID(postID) + "/smiles", query: [("from", source)],
                           method: enabled ? "PUT" : "DELETE", authenticated: true)
    }
    public func markRead(ids: [String], feed: Feed) async throws {
        guard !ids.isEmpty, ids.count <= 30, ids.allSatisfy(Wire.validID) else { throw ClientError.invalidInput }
        _ = try await call(path: "reads/" + ids.joined(separator: ","), query: [("from", feed.source)], method: "PUT", authenticated: true)
    }

    // Native Android Retrofit contracts. All writes use the existing account
    // fence and single-attempt transport; none are automatically replayed.
    public func unsmile(postID: String, enabled: Bool, source: String, session: UUID? = nil) async throws {
        try validateWriteSession(session)
        guard ["feat", "coll", "subs", "prof"].contains(source) else { throw ClientError.invalidInput }
        _ = try await call(path: "content/" + Wire.requireID(postID) + "/unsmiles", query: [("from", source)], method: enabled ? "PUT" : "DELETE", authenticated: true)
    }
    public func republish(postID: String, enabled: Bool, source: String, session: UUID? = nil) async throws {
        try validateWriteSession(session)
        guard ["feat", "coll", "subs", "prof"].contains(source) else { throw ClientError.invalidInput }
        _ = try await call(path: "content/" + Wire.requireID(postID) + "/republished", query: [("from", source)], method: enabled ? "POST" : "DELETE", authenticated: true)
    }
    public func reactToComment(postID: String, commentID: String, unsmile: Bool, enabled: Bool, session: UUID? = nil) async throws {
        try validateWriteSession(session)
        let path = "content/" + (try Wire.requireID(postID)) + "/comments/" + (try Wire.requireID(commentID)) + (unsmile ? "/unsmiles" : "/smiles")
        _ = try await call(path: path, method: enabled ? "PUT" : "DELETE", authenticated: true)
    }
    public func deleteComment(postID: String, commentID: String, session: UUID? = nil) async throws {
        try validateWriteSession(session)
        let path = "content/" + (try Wire.requireID(postID)) + "/comments/" + (try Wire.requireID(commentID))
        _ = try await call(path: path, method: "DELETE", authenticated: true)
    }
    public func deleteComments(postID: String, commentIDs: [String], session: UUID) async throws -> CommentDeletionReceipt {
        try validateWriteSession(session)
        let ids = try CommentDeletionReceipt.selectionField(commentIDs)
        let response = try await call(path: "content/" + Wire.requireID(postID) + "/comments", query: [("method", "DELETE")],
            method: "POST", fields: [("id", ids)], authenticated: true)
        return try CommentDeletionReceipt(response, requested: commentIDs)
    }
    public func reportComment(postID: String, commentID: String, session: UUID? = nil) async throws {
        try validateWriteSession(session)
        let path = "content/" + (try Wire.requireID(postID)) + "/comments/" + (try Wire.requireID(commentID)) + "/abuses"
        _ = try await call(path: path, method: "PUT", authenticated: true)
    }

    public func profile(userID: String) async throws -> UserProfile {
        let data = try await call(path: "users/" + Wire.requireID(userID))["data"]
        let user = try UserProfile(data["user"] == .null ? data : data["user"])
        guard user.id == userID else { throw ClientError.malformedResponse }; return user
    }
    public func profileTimeline(userID: String, featured: Bool = false, next: String? = nil) async throws -> PostPage {
        if let next, next.utf8.count > 8192 { throw ClientError.invalidInput }
        var query = [("limit", "30")]; if let next { query.append(("next", next)) }
        let path = "timelines/users/" + (try Wire.requireID(userID)) + (featured ? "/featured" : "")
        let data = try await call(path: path, query: query)["data"]
        guard case .object = data["content"]["paging"] else { throw ClientError.malformedResponse }
        return try PostPage(data)
    }
    public func users(userID: String, kind: UserListKind, next: String? = nil) async throws -> UserPage {
        if let next, next.utf8.count > 8192 { throw ClientError.invalidInput }
        var query = [("limit", "30")]; if let next { query.append(("next", next)) }
        return try UserPage(await call(path: "users/" + Wire.requireID(userID) + "/" + kind.rawValue, query: query)["data"])
    }
    public func searchUsers(_ text: String, next: String? = nil) async throws -> UserPage {
        guard text.utf8.count <= 1024, next == nil || next!.utf8.count <= 8192 else { throw ClientError.invalidInput }
        var query = [("q", text), ("limit", "30")]; if let next { query.append(("next", next)) }
        return try UserPage(await call(path: "search/users", query: query)["data"])
    }
    public func setSubscribed(userID: String, enabled: Bool, session: UUID) async throws -> UserProfile {
        guard session == epoch else { throw ClientError.sessionChanged }
        guard let credential else { throw ClientError.signInRequired }
        guard credential.accountID != userID else { throw ClientError.invalidInput }
        _ = try await call(path: "users/" + Wire.requireID(userID) + "/subscribers", method: enabled ? "PUT" : "DELETE", authenticated: true)
        let user = try await profile(userID: userID)
        guard session == epoch else { throw ClientError.sessionChanged }
        guard user.isSubscribed == enabled else { throw ProfileActionError.unconfirmed }; return user
    }
    private var pinFlights = Set<String>()
    public func suggestedTags(_ query: String) async throws -> SuggestedTags {
        let query = ProfileSearchCriteria.normalized(query)
        guard (2...100).contains(query.utf16.count) else { throw ClientError.invalidInput }
        return try SuggestedTags(await call(path: "tags/suggested", query: [("q", query)])["data"])
    }
    public func setProfilePin(userID: String, postID: String, enabled: Bool, session: UUID) async throws -> PostPage {
        guard session == epoch else { throw ClientError.sessionChanged }
        guard credential?.accountID == userID else { throw ClientError.signInRequired }
        _ = try Wire.requireID(postID)
        guard pinFlights.insert(userID).inserted else { throw ProfileActionError.unconfirmed }
        defer { pinFlights.remove(userID) }
        let before = try await profileTimeline(userID: userID)
        guard session == epoch else { throw ClientError.sessionChanged }
        let pins = Set(before.posts.filter(\.isPinned).map(\.id))
        if pins.contains(postID) == enabled { return before }
        guard !enabled || pins.count < 3 else { throw ProfileActionError.pinLimit }
        _ = try await call(path: "content/" + Wire.requireID(postID) + "/pinned", method: enabled ? "PUT" : "DELETE", authenticated: true)
        let after = try await profileTimeline(userID: userID)
        guard session == epoch else { throw ClientError.sessionChanged }
        let confirmed = Set(after.posts.filter(\.isPinned).map(\.id))
        guard confirmed.contains(postID) == enabled, confirmed.count <= 3 else { throw ProfileActionError.unconfirmed }
        return after
    }
}
