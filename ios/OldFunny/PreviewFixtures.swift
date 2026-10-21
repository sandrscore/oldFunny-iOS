// Included only in the separate simulator preview configuration. This code is
// absent from the Release IPA; it uses no real service, credential or session.
#if CLASSIC_UI_PREVIEW
import UIKit

private struct PreviewStore: CredentialStore {
    func read() throws -> Credential? {
        guard ProcessInfo.processInfo.arguments.contains("--ui-tests-account") else { return nil }
        // Fabricated fixture identity; never Keychain data or a usable session.
        return try Credential(accessToken: "offline-fixture-not-a-session", refreshToken: nil, accountID: "PreviewUser", nickname: "ClassicFan")
    }
    func write(_ credential: Credential) throws { throw ClientError.invalidInput }
    func erase() throws {}
}

private actor PreviewTransport: HTTPTransport {
    private var sentReplies = [[String: Any]](), deleted = Set<String>()
    private var profilePins = Set<String>(), subscriptions = Set<String>()
    private var replyCount: Int { 2 + sentReplies.count - deleted.filter { $0.hasPrefix("PreviewReply") || $0.hasPrefix("FixtureSentReply") }.count }
    func send(_ request: URLRequest) async throws -> HTTPResult {
        let path = request.url?.path ?? "", method = request.httpMethod ?? "GET"
        if ProcessInfo.processInfo.arguments.contains("--ui-tests-profile") || ProcessInfo.processInfo.arguments.contains("--preview-profile") {
            if let result = try profileRequest(request) { return result }
        }
        if ProcessInfo.processInfo.arguments.contains("--ui-tests-reactions"), ["PUT", "DELETE"].contains(method), path == "/v4/content/PreviewPost/smiles" || path == "/v4/content/PreviewPost/unsmiles" {
            await MainActor.run { PreviewFixtures.reactionEvents.append(request.url!.lastPathComponent) }
            return HTTPResult(status: 204, body: Data())
        }
        // Explicit, per-launch offline acknowledgements for the count/state UI
        // test. No URLSession or real service is available in this transport.
        if ProcessInfo.processInfo.arguments.contains("--ui-tests-accepted-comments") {
            if method == "POST", path.hasSuffix("/replies") {
                let parent = request.url!.deletingLastPathComponent().lastPathComponent
                let parents = ["PreviewComment1", "PreviewReply1", "PreviewReply2"] + sentReplies.compactMap { $0["id"] as? String }
                guard path.hasPrefix("/v4/content/PreviewPost/comments/"), parents.contains(parent), !deleted.contains(parent) else { throw ClientError.invalidInput }
                let fields = String(decoding: request.httpBody ?? Data(), as: UTF8.self).split(separator: "&").reduce(into: [String: String]()) { result, pair in
                    let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                    if parts.count == 2 { result[String(parts[0])] = String(parts[1]).replacingOccurrences(of: "+", with: " ").removingPercentEncoding }
                }
                sentReplies.append(["id": "FixtureSentReply\(sentReplies.count + 1)", "text": fields["text"] ?? "", "user": ["id": "PreviewUser", "nick": "ClassicFan"], "root_comm_id": "PreviewComment1", "parent_comm_id": request.url!.deletingLastPathComponent().lastPathComponent, "depth": 1])
                return HTTPResult(status: 204, body: Data())
            }
            if method == "DELETE", path.contains("/comments/") {
                let id = request.url!.lastPathComponent
                let known = ["PreviewComment1", "PreviewComment2", "PreviewComment3", "PreviewReply1", "PreviewReply2"] + sentReplies.compactMap { $0["id"] as? String }
                guard path.hasPrefix("/v4/content/PreviewPost/comments/"), known.contains(id), !deleted.contains(id) else { throw ClientError.invalidInput }
                deleted.insert(id); return HTTPResult(status: 204, body: Data())
            }
        }
        guard method == "GET" || (method == "POST" && path == "/v4/feeds/collective") else { throw ClientError.invalidInput }
        let value: String
        if path.contains("/replies") {
            var root = try JSONSerialization.jsonObject(with: Data(PreviewFixtures.replies.utf8)) as! [String: Any]
            var data = root["data"] as! [String: Any], replies = data["replies"] as! [String: Any]
            let rows = (replies["items"] as! [[String: Any]]) + sentReplies
            replies["items"] = rows.map { row -> [String: Any] in var row = row; if deleted.contains(row["id"] as! String) { row["state"] = "deleted_self" }; return row }
            data["replies"] = replies; data["comment"] = ["replies_count": replyCount]; root["data"] = data
            return HTTPResult(status: 200, body: try JSONSerialization.data(withJSONObject: root))
        }
        else if path.contains("comments") {
            var root = try JSONSerialization.jsonObject(with: Data(PreviewFixtures.comments.utf8)) as! [String: Any]
            var data = root["data"] as! [String: Any], comments = data["comments"] as! [String: Any]
            comments["items"] = (comments["items"] as! [[String: Any]]).map { row -> [String: Any] in
                var row = row
                if row["id"] as? String == "PreviewComment1" { row["num"] = ["replies": replyCount] }
                if deleted.contains(row["id"] as! String) { row["state"] = "deleted_self" }
                return row
            }
            data["comments"] = comments; root["data"] = data
            return HTTPResult(status: 200, body: try JSONSerialization.data(withJSONObject: root))
        }
        else if request.url?.path.contains("feeds") == true || request.url?.path.contains("timelines") == true {
            // This fixture has three roots and two replies. The normal visual
            // fixture keeps its historical count; mutation tests use the total.
            value = ProcessInfo.processInfo.arguments.contains("--ui-tests-accepted-comments")
                ? PreviewFixtures.feed.replacingOccurrences(of: "\"comments\":3", with: "\"comments\":\(5 + sentReplies.count - deleted.count)") : PreviewFixtures.feed
        }
        else { throw ClientError.invalidInput }
        return HTTPResult(status: 200, body: Data(value.utf8))
    }
    private func profileRequest(_ request: URLRequest) throws -> HTTPResult? {
        let path = request.url!.path, method = request.httpMethod ?? "GET"
        let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func response(_ data: [String: Any]) throws -> HTTPResult { HTTPResult(status: 200, body: try JSONSerialization.data(withJSONObject: ["status": 200, "data": data])) }
        func user(_ id: String) -> [String: Any] {
            ["id": id, "nick": id == "PreviewUser" ? "ClassicFan" : id == "Writer" ? "Writer" : "ReaderOne", "about": "Offline profile fixture.", "avatar": ["s": "https://preview.invalid/avatar"], "cover_url": "https://preview.invalid/cover", "num": ["created": 44, "featured": 5, "subscribers": 2, "subscriptions": 3], "is_in_subscriptions": subscriptions.contains(id)]
        }
        if method != "GET" {
            guard ProcessInfo.processInfo.arguments.contains("--ui-tests-profile-writes") else { return nil }
            if path.hasPrefix("/v4/content/GridPost"), path.hasSuffix("/pinned"), ["PUT", "DELETE"].contains(method) {
                let id = request.url!.deletingLastPathComponent().lastPathComponent
                guard (0..<44).map({ "GridPost\($0)" }).contains(id) else { throw ClientError.invalidInput }
                if method == "PUT" { guard profilePins.count < 3 || profilePins.contains(id) else { throw ClientError.http(409) }; profilePins.insert(id) }
                else { profilePins.remove(id) }
                return HTTPResult(status: 204, body: Data())
            }
            if path.hasPrefix("/v4/users/"), path.hasSuffix("/subscribers"), ["PUT", "DELETE"].contains(method) {
                let id = request.url!.deletingLastPathComponent().lastPathComponent
                if method == "PUT" { subscriptions.insert(id) } else { subscriptions.remove(id) }
                return HTTPResult(status: 204, body: Data())
            }
            return nil
        }
        if path.hasPrefix("/v4/timelines/users/") {
            let featured = path.hasSuffix("/featured")
            let owner = request.url!.pathComponents[4], ownerName = user(request.url!.pathComponents[4])["nick"] as! String
            var rows = (0..<44).map { index -> [String: Any] in
                var row: [String: Any] = ["id": "GridPost\(index)", "type": "pic", "url": "https://preview.invalid/post", "thumb": ["large_url": "https://preview.invalid/thumb/GridPost\(index)"], "size": ["w": 640, "h": 760], "state": "published", "creator": ["id": owner, "nick": ownerName], "is_featured": index % 10 == 0, "is_pinned": profilePins.contains("GridPost\(index)"), "tags": index % 2 == 0 ? ["cats", "fun"] : ["dogs"], "num": ["smiles": index + 1, "comments": 0]]
                if index % 5 == 0 && index % 10 != 0 { row["source"] = ["creator": ["id": "Writer", "nick": "Writer"]] }
                return row
            }
            rows.sort { lhs, rhs in
                let a = lhs["is_pinned"] as! Bool, b = rhs["is_pinned"] as! Bool
                if a != b { return a }
                return Int(String((lhs["id"] as! String).dropFirst(8)))! < Int(String((rhs["id"] as! String).dropFirst(8)))!
            }
            if featured { rows = rows.filter { $0["is_featured"] as! Bool } }
            let offset = query.first { $0.name == "next" }?.value == "profile-next" ? 30 : 0
            let slice = Array(rows.dropFirst(offset).prefix(30)), more = rows.count > offset + slice.count
            return try response(["content": ["items": slice, "paging": ["hasNext": more, "cursors": more ? ["next": "profile-next"] : [:]]]])
        }
        if path == "/v4/search/users" {
            let text = (query.first { $0.name == "q" }?.value ?? "").lowercased()
            let rows = [user("Writer"), user("Reader1")].filter { ($0["nick"] as! String).lowercased().contains(text) }
            return try response(["users": ["items": rows, "paging": ["hasNext": false]]])
        }
        if path.hasPrefix("/v4/users/") {
            let component = request.url!.lastPathComponent
            if ["subscribers", "subscriptions"].contains(component) { return try response(["users": ["items": [user("Writer"), user("Reader1")], "paging": ["hasNext": false]]]) }
            return try response(user(component))
        }
        return nil
    }
}

enum PreviewFixtures {
    @MainActor static var reactionEvents = [String]()
    @MainActor static func makeApp() throws -> AppContext {
        let api = try APIClient(installation: String(repeating: "a", count: 64), userAgent: "Offline UI preview", store: PreviewStore(), transport: PreviewTransport())
        return AppContext(previewAPI: api)
    }
    static let post = #"{"id":"PreviewPost","type":"picture","url":"https://preview.invalid/post","size":{"w":640,"h":760},"creator":{"id":"PreviewUser","nick":"ClassicFan","avatar":{"s":"https://preview.invalid/avatar"}},"num":{"smiles":128,"comments":3}}"#
    static var feed: String {
        let second = post.replacingOccurrences(of: "PreviewPost", with: "NextPost").replacingOccurrences(of: "ClassicFan", with: "NextFan")
        let first = ProcessInfo.processInfo.arguments.contains("--ui-tests-video")
            ? post.replacingOccurrences(of: "\"type\":\"picture\"", with: "\"type\":\"video\"")
                .replacingOccurrences(of: "https://preview.invalid/post", with: "https://preview.invalid/fixture-video.mp4")
                .replacingOccurrences(of: "\"h\":760", with: "\"h\":360") : post
        return "{\"status\":200,\"data\":{\"content\":{\"items\":[\(first),\(second)],\"paging\":{\"hasNext\":false}}}}"
    }
    static var comments: String {
        """
        {"status":200,"data":{"comments":{"items":[
          {"id":"PreviewComment1","user":{"id":"PreviewUser","nick":"ClassicFan","photo":{"thumb":{"small_url":"https://preview.invalid/avatar"}}},"date":1792418400,"text":"The classic look is coming back.","num":{"replies":2}},
          {"id":"PreviewComment2","creator":{"id":"AnotherUser","nick":"AnotherUser","avatar":{"s":"https://preview.invalid/avatar2"}},"date":1792418400,"text":"An attached post, right in the thread.","attachments":{"content":[\(post)]}},
          {"id":"PreviewComment3","user":{"id":"Reader","nick":"Reader"},"text":"Same feed. Familiar controls.","num":{"replies":0}}
        ],"paging":{"hasNext":false}}}}
        """
    }
    static let replies = #"{"status":200,"data":{"comment":{"replies_count":2},"replies":{"items":[{"id":"PreviewReply1","user":{"id":"Reader1","nick":"ReaderOne"},"text":"Reply number one","root_comm_id":"PreviewComment1","parent_comm_id":"PreviewComment1","depth":1,"num":{"smiles":2}},{"id":"PreviewReply2","user":{"id":"Reader2","nick":"ReaderTwo"},"text":"Reply number two","root_comm_id":"PreviewComment1","parent_comm_id":"PreviewReply1","depth":2}],"paging":{"hasNext":false}}}}"#
    @MainActor static func image(_ url: URL) -> UIImage {
        let isAvatar = url.path.contains("avatar")
        let size = isAvatar ? CGSize(width: 96, height: 96) : CGSize(width: 640, height: 760)
        return UIGraphicsImageRenderer(size: size).image { context in
            UIColor(white: isAvatar ? 0.25 : 0.90, alpha: 1).setFill(); context.fill(CGRect(origin: .zero, size: size))
            let side: CGFloat = isAvatar ? 70 : 240
            let circle = CGRect(x: (size.width - side) / 2, y: isAvatar ? 13 : 220, width: side, height: side)
            ClassicTheme.yellow.setFill(); UIBezierPath(ovalIn: circle).fill()
            UIColor.black.setFill(); UIColor.black.setStroke()
            let eye = side * 0.08
            UIBezierPath(ovalIn: CGRect(x: circle.minX + side * 0.62, y: circle.minY + side * 0.27, width: eye, height: eye)).fill()
            UIBezierPath(roundedRect: CGRect(x: circle.minX + side * 0.20, y: circle.minY + side * 0.24, width: side * 0.24, height: side * 0.16), cornerRadius: side * 0.04).fill()
            let mouth = UIBezierPath(); mouth.lineWidth = max(2, side * 0.045)
            mouth.addArc(withCenter: CGPoint(x: circle.midX, y: circle.midY), radius: side * 0.27, startAngle: 0.25, endAngle: .pi - 0.25, clockwise: true); mouth.stroke()
            if !isAvatar {
                let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center
                ("oldFunny" as NSString).draw(in: CGRect(x: 25, y: 65, width: 590, height: 80), withAttributes: [.font: UIFont(name: "HelveticaNeue-Bold", size: 64)!, .foregroundColor: UIColor.black, .paragraphStyle: paragraph])
                ("Back to the classic feed." as NSString).draw(in: CGRect(x: 25, y: 565, width: 590, height: 55), withAttributes: [.font: UIFont(name: "HelveticaNeue", size: 31)!, .foregroundColor: UIColor.black, .paragraphStyle: paragraph])
            }
        }
    }
}
#endif
