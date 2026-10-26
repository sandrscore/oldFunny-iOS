import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Read the website's JSON as data, matching revival.WebPostData. No script runs.
public enum PublicPicture {
    public static func parse(_ html: Data, id: String) throws -> Post? {
        guard Wire.validID(id), id.utf8.count <= 40, html.count <= 2 * 1024 * 1024,
              let text = String(data: html, encoding: .utf8) else { return nil }
        let marker = try NSRegularExpression(pattern: #"<script[^>]*>\s*window\.__INITIAL_STATE__\s*=\s*"#, options: .caseInsensitive)
        guard let match = marker.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text) else { return nil }
        let bytes = Array(text[range.upperBound...].utf8)
        guard bytes.first == 123 else { return nil }
        var depth = 0, quoted = false, escaped = false, end: Int?
        for (index, byte) in bytes.enumerated() {
            if quoted {
                if escaped { escaped = false }
                else if byte == 92 { escaped = true }
                else if byte == 34 { quoted = false }
            } else if byte == 34 { quoted = true }
            else if byte == 123 { depth += 1 }
            else if byte == 125 { depth -= 1; if depth == 0 { end = index + 1; break } }
        }
        guard let end, let state = try? JSON.decode(Data(bytes[..<end])) else { return nil }
        guard let row = state["feed"]["items"].items.first(where: {
            $0["id"].string == id && $0["type"].string == "picture" && $0["state"].string == "published" && $0["isAbused"].flag != true
        }), let url = Wire.https(row["url"].string),
            case .number(let width) = row["size"]["w"], case .number(let height) = row["size"]["h"], width >= 1, height >= 1 else { return nil }
        var thumb = [String: JSON]()
        for (from, to) in [("m", "url"), ("l", "large_url"), ("xl", "x640_url"), ("p", "proportional_url")] {
            thumb[to] = .string(CommentAttachment.webURL(row["thumb"][from].string)?.absoluteString ?? "")
        }
        thumb["proportional_size"] = row["thumb"]["pSize"]
        let creator = row["creator"]
        let avatar = creator["avatar"].string ?? creator["avatar"]["url"].string
        let user: JSON = .object(["id": creator["id"], "nick": creator["nick"], "photo": .object(["url": .string(avatar ?? ""), "thumb": .object(["small_url": .string(avatar ?? "")])])])
        return try Post(.object([
            "id": .string(id), "type": .string("pic"), "state": .string("published"), "url": .string(url.absoluteString), "size": row["size"],
            "date_create": row["created"], "title": row["title"], "creator": user, "thumb": .object(thumb),
            "is_featured": row["isFeatured"], "is_republished": row["isRepublished"],
            "num": .object(["smiles": row["smiles"], "comments": row["comments"]]),
            "tags": .array(row["tags"].items.compactMap { tag in (tag.string ?? tag["name"].string).flatMap { $0.isEmpty ? nil : .string($0) } })
        ]))
    }
}

/// Website requests never share API credentials, cookies or authentication redirects.
public final class PublicPictureTransport: NSObject, HTTPTransport, URLSessionTaskDelegate, @unchecked Sendable {
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false; config.httpCookieStorage = nil; config.urlCache = nil
        config.timeoutIntervalForRequest = 8; config.timeoutIntervalForResource = 16
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()
    public override init() { super.init(); _ = session }
    private func allowed(_ request: URLRequest) -> Bool {
        request.httpMethod == "GET" && request.value(forHTTPHeaderField: "Authorization") == nil &&
        request.value(forHTTPHeaderField: "Cookie") == nil && request.url?.scheme == "https" &&
        ["ifunny.co", "www.ifunny.co"].contains(request.url?.host?.lowercased() ?? "") && request.url?.user == nil && request.url?.password == nil
    }
    public func send(_ request: URLRequest) async throws -> HTTPResult {
        guard allowed(request) else { throw ClientError.invalidInput }
        do {
            let (file, response) = try await session.download(for: request)
            defer { try? FileManager.default.removeItem(at: file) }
            try Task.checkCancellation()
            let size = (try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.intValue ?? 0
            guard let http = response as? HTTPURLResponse, size <= 2 * 1024 * 1024 else { throw ClientError.malformedResponse }
            return HTTPResult(status: http.statusCode, body: try Data(contentsOf: file))
        } catch is CancellationError { throw CancellationError() }
        catch let error as ClientError { throw error }
        catch let error as URLError where error.code == .cancelled { throw CancellationError() }
        catch { throw ClientError.networkFailure(error) }
    }
    public func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                           newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(allowed(request) ? request : nil)
    }
}
