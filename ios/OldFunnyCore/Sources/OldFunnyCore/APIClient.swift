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
    private let store: any CredentialStore
    private let userAgent: String
    private var credential: Credential?
    private var epoch = UUID()
    private var refreshFlight: (owner: UUID, task: Task<Credential, Error>)?

    public init(installation: String, userAgent: String, store: any CredentialStore,
                transport: any HTTPTransport = URLTransport()) throws {
        _ = try Wire.basic(installation: installation)
        self.installation = installation; self.userAgent = userAgent
        self.store = store; self.transport = transport
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
        return try Self.parse(response)
    }

    public func feed(_ feed: Feed, next: String? = nil) async throws -> PostPage {
        if let next, next.utf8.count > 8192 { throw ClientError.invalidInput }
        var query = [("limit", "30")]
        if let next { query.append(("next", next)) }
        return try PostPage(await call(path: feed.path, query: query, authenticated: feed == .subscriptions)["data"])
    }
    public func timeline(userID: String, next: String? = nil) async throws -> PostPage {
        var query = [("limit", "30")]
        if let next, next.utf8.count <= 8192 { query.append(("next", next)) }
        return try PostPage(await call(path: "timelines/users/" + Wire.requireID(userID), query: query)["data"])
    }
    public func comments(postID: String, parentID: String? = nil, next: String? = nil) async throws -> CommentPage {
        var path = "content/" + (try Wire.requireID(postID)) + "/comments"
        if let parentID { path += "/" + (try Wire.requireID(parentID)) + "/replies" }
        var query = [("limit", "30"), ("from", "feat")]
        if let next, next.utf8.count <= 8192 { query.append(("next", next)) }
        return try CommentPage(await call(path: path, query: query)["data"], replies: parentID != nil)
    }
    public func sendComment(postID: String, parentID: String? = nil, text: String, attachmentID: String? = nil) async throws {
        guard text.utf16.count <= 300, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || attachmentID != nil else {
            throw ClientError.invalidInput
        }
        var path = "content/" + (try Wire.requireID(postID)) + "/comments"
        if let parentID { path += "/" + (try Wire.requireID(parentID)) + "/replies" }
        var fields = [("text", text)]
        if let attachmentID { fields.append(("content", try Wire.requireID(attachmentID))) }
        _ = try await call(path: path, method: "POST", fields: fields, authenticated: true)
    }
    public func smile(postID: String, enabled: Bool, source: String) async throws {
        guard ["feat", "subs", "prof"].contains(source) else { throw ClientError.invalidInput }
        _ = try await call(path: "content/" + Wire.requireID(postID) + "/smiles", query: [("from", source)],
                           method: enabled ? "PUT" : "DELETE", authenticated: true)
    }
    public func markRead(ids: [String], feed: Feed) async throws {
        guard !ids.isEmpty, ids.count <= 30, ids.allSatisfy(Wire.validID) else { throw ClientError.invalidInput }
        _ = try await call(path: "reads/" + ids.joined(separator: ","), query: [("from", feed.source)], method: "PUT", authenticated: true)
    }
}
