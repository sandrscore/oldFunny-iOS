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
    private var mentionSends = 0
    private var bulkSends = 0, bulkRemovedRoots = Set<String>()
    private var bulkReadFailures = 0
    private var attachmentPageReads = 0
    private var replyCount: Int { 2 + sentReplies.count - deleted.filter { $0.hasPrefix("PreviewReply") || $0.hasPrefix("FixtureSentReply") }.count }
    func send(_ request: URLRequest) async throws -> HTTPResult {
        let path = request.url?.path ?? "", method = request.httpMethod ?? "GET"
        if ProcessInfo.processInfo.arguments.contains("--ui-tests-attachment-cards"), method == "GET" {
            if path == "/v4/content/AttachedPic" {
                await MainActor.run { PreviewFixtures.attachmentReads.append("api:AttachedPic") }
                return HTTPResult(status: 404, body: Data())
            }
            if request.url?.host == "ifunny.co", path == "/picture/AttachedPic" {
                guard request.value(forHTTPHeaderField: "Authorization") == nil, request.value(forHTTPHeaderField: "Cookie") == nil else { throw ClientError.invalidInput }
                await MainActor.run { PreviewFixtures.attachmentReads.append("web:AttachedPic") }
                return HTTPResult(status: 200, body: Data(PreviewFixtures.publicAttachmentPicture.utf8))
            }
            if path == "/v4/content/AttachedVideo" {
                let data = PreviewFixtures.post.replacingOccurrences(of: "PreviewPost", with: "AttachedVideo")
                return HTTPResult(status: 200, body: Data(("{\"status\":200,\"data\":" + data + "}").utf8))
            }
        }
        if ProcessInfo.processInfo.arguments.contains("--ui-tests-bulk-delete"), method == "POST", path == "/v4/content/PreviewPost/comments",
           URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.contains(URLQueryItem(name: "method", value: "DELETE")) == true {
            let encoded = String(decoding: request.httpBody ?? Data(), as: UTF8.self).replacingOccurrences(of: "+", with: "%20")
            let fields = URLComponents(string: "?" + encoded)?.queryItems ?? []
            let csv = fields.first { $0.name == "id" }?.value ?? "", ids = csv.components(separatedBy: ",")
            let known = ["PreviewComment1", "PreviewComment2", "PreviewComment3", "PreviewReply1", "PreviewReply2"]
            guard !ids.isEmpty, Set(ids).count == ids.count, ids.allSatisfy({ known.contains($0) && !deleted.contains($0) }), fields.count == 1 else { throw ClientError.invalidInput }
            bulkSends += 1; let record = "\(bulkSends)|POST|\(path)?method=DELETE|id=\(csv)"
            await MainActor.run { PreviewFixtures.bulkRequest = record }
            if ProcessInfo.processInfo.arguments.contains("--ui-tests-bulk-uncertain") { bulkReadFailures = 1; throw ClientError.transport }
            var accepted = ids, responses = [[String: Any]]()
            if ProcessInfo.processInfo.arguments.contains("--ui-tests-bulk-partial") {
                guard ids == ["PreviewComment1", "PreviewComment2"] else { throw ClientError.invalidInput }
                accepted = ["PreviewComment1"]; responses = [["status": 204], ["status": 403]]
            }
            for id in accepted {
                deleted.insert(id)
                if id.hasPrefix("PreviewComment") { bulkRemovedRoots.insert(id) }
                if id == "PreviewComment1" { deleted.formUnion(["PreviewReply1", "PreviewReply2"]) }
            }
            return HTTPResult(status: 200, body: try JSONSerialization.data(withJSONObject: ["status": 200, "data": ["responses": responses]]))
        }
        if ProcessInfo.processInfo.arguments.contains("--ui-tests-mentions"), let result = try await mentionRequest(request) { return result }
        let mentionedProfile = ProcessInfo.processInfo.arguments.contains("--ui-tests-mentions") && (path.hasPrefix("/v4/users/Reader2") || path.hasPrefix("/v4/timelines/users/Reader2"))
        if ProcessInfo.processInfo.arguments.contains("--ui-tests-profile") || ProcessInfo.processInfo.arguments.contains("--preview-profile") || ProcessInfo.processInfo.arguments.contains("--preview-profile-search") || mentionedProfile {
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
                deleted.insert(id)
                if id.hasPrefix("PreviewComment") { bulkRemovedRoots.insert(id) }
                if id == "PreviewComment1" {
                    deleted.formUnion(["PreviewReply1", "PreviewReply2"] + sentReplies.compactMap { $0["id"] as? String })
                }
                return HTTPResult(status: 204, body: Data())
            }
        }
        guard method == "GET" || (method == "POST" && path == "/v4/feeds/collective") else { throw ClientError.invalidInput }
        if method == "GET", path.contains("/comments"), ProcessInfo.processInfo.arguments.contains("--ui-tests-comment-options") {
            let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
            guard items == [URLQueryItem(name: "limit", value: "40")] else { throw ClientError.invalidInput }
        }
        let value: String
        if path.contains("/replies") {
            var root = try JSONSerialization.jsonObject(with: Data(PreviewFixtures.replies.utf8)) as! [String: Any]
            var data = root["data"] as! [String: Any], replies = data["replies"] as! [String: Any]
            let rows = (replies["items"] as! [[String: Any]]) + sentReplies
            replies["items"] = rows.map { row -> [String: Any] in var row = row; if ProcessInfo.processInfo.arguments.contains("--ui-tests-comment-options") { row["depth"] = row["id"] as? String == "PreviewReply1" ? 29 : 30 }; if deleted.contains(row["id"] as! String) { row["state"] = "deleted_self" }; return row }
            data["replies"] = replies; data["comment"] = ["replies_count": replyCount]; root["data"] = data
            return HTTPResult(status: 200, body: try JSONSerialization.data(withJSONObject: root))
        }
        else if path.contains("comments") {
            if bulkReadFailures > 0 { bulkReadFailures -= 1; return HTTPResult(status: 503, body: Data()) }
            if ProcessInfo.processInfo.arguments.contains("--ui-tests-attachment-cards") { attachmentPageReads += 1 }
            var root = try JSONSerialization.jsonObject(with: Data(PreviewFixtures.comments.utf8)) as! [String: Any]
            var data = root["data"] as! [String: Any], comments = data["comments"] as! [String: Any]
            comments["items"] = (comments["items"] as! [[String: Any]]).filter { !bulkRemovedRoots.contains($0["id"] as! String) }.map { row -> [String: Any] in
                var row = row
                if row["id"] as? String == "PreviewComment1" { row["num"] = ["replies": replyCount] }
                if ProcessInfo.processInfo.arguments.contains("--ui-tests-attachment-cards"), attachmentPageReads > 1, row["id"] as? String == "Withheld" {
                    row["attachments"] = ["content": [], "content_from_links": [
                        ["id": "AttachedVideo", "type": "video_clip", "thumb": ["url": "https://preview.invalid/comment-gif"], "size": ["w": 400, "h": 300]],
                        ["id": "BlockedCreator", "creator": ["is_blocked": true], "thumb": ["url": "https://preview.invalid/never-load"]]
                    ]]
                }
                if ProcessInfo.processInfo.arguments.contains("--ui-tests-mentions"), row["id"] as? String == "PreviewComment1" {
                    row["text"] = "ReaderTwo says hello."
                    row["attachments"] = ["mention_user": [["user_id": "Reader2", "nick": "ReaderTwo", "start_index": 0, "stop_index": 8]]]
                }
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
    private func mentionRequest(_ request: URLRequest) async throws -> HTTPResult? {
        let path = request.url!.path, method = request.httpMethod ?? "GET"
        let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func field(_ name: String) -> String? { query.first { $0.name == name }?.value }
        func response(_ users: [[String: Any]], next: String? = nil) throws -> HTTPResult {
            HTTPResult(status: 200, body: try JSONSerialization.data(withJSONObject: ["status": 200, "data": ["users": ["items": users, "paging": ["hasNext": next != nil, "cursors": next.map { ["next": $0] } ?? [:]]]]]))
        }
        func user(_ id: String, _ name: String) -> [String: Any] { ["id": id, "nick": name, "is_in_subscribers": true, "is_in_subscriptions": true, "photo": ["thumb": ["small_url": "https://preview.invalid/avatar/" + id]]] }
        if method == "GET", path == "/v4/users/my/mention_users" {
            guard field("limit") == "9", request.value(forHTTPHeaderField: "Authorization") == "Bearer offline-fixture-not-a-session" else { throw ClientError.invalidInput }
            return try response([user("Reader1", "ReaderOne"), user("Reader2", "ReaderTwo")])
        }
        if method == "GET", path == "/v4/search/users_for_mentions" {
            guard field("limit") == "20", field("q") == "re" else { throw ClientError.invalidInput }
            if field("next") == nil { return try response([user("Reader1", "ReaderOne")], next: "mention-next") }
            guard field("next") == "mention-next" else { throw ClientError.invalidInput }
            return try response([user("Reader1", "ReaderOne"), user("Reader2", "ReaderTwo")])
        }
        if method == "POST", ["/v4/content/PreviewPost/comments", "/v4/content/PreviewPost/comments/PreviewReply1/replies"].contains(path) {
            let encoded = String(decoding: request.httpBody ?? Data(), as: UTF8.self).replacingOccurrences(of: "+", with: "%20")
            let fields = URLComponents(string: "?" + encoded)?.queryItems ?? []
            func value(_ name: String) -> String { fields.first { $0.name == name }?.value ?? "" }
            mentionSends += 1
            let record = "\(mentionSends)|\(path)|text=\(value("text"))|mentions=\(value("user_mentions"))|content=\(value("content"))"
            await MainActor.run { PreviewFixtures.mentionRequest = record }
            // A deliberate uncertain receipt retains the exact draft. Tests
            // assert the recorded form independently of the production parser.
            if !ProcessInfo.processInfo.arguments.contains("--ui-tests-mention-success") { throw ClientError.transport }
            guard path.hasSuffix("/PreviewReply1/replies"), value("text") == "Hello ReaderTwo", value("user_mentions") == "Reader2:6:14", value("content") == "PreviewPost" else { throw ClientError.invalidInput }
            sentReplies.append(["id": "FixtureSentReply1", "text": "Hello ReaderTwo", "user": ["id": "PreviewUser", "nick": "ClassicFan"], "root_comm_id": "PreviewComment1", "parent_comm_id": "PreviewReply1", "depth": 2, "attachments": ["mention_user": [["user_id": "Reader2", "nick": "ReaderTwo", "start_index": 6, "stop_index": 14]]]])
            return HTTPResult(status: 204, body: Data())
        }
        return nil
    }
    private func profileRequest(_ request: URLRequest) throws -> HTTPResult? {
        let path = request.url!.path, method = request.httpMethod ?? "GET"
        let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func response(_ data: [String: Any]) throws -> HTTPResult { HTTPResult(status: 200, body: try JSONSerialization.data(withJSONObject: ["status": 200, "data": data])) }
        if method == "GET", path == "/v4/tags/suggested" {
            let q = query.first { $0.name == "q" }?.value ?? ""
            return try response(["tags": ["items": ["dogs", "cats", "fun", "cat_pictures"].filter { $0.hasPrefix(q) }.map { ["tag": $0] }, "paging": ["hasNext": false]]])
        }
        func user(_ id: String) -> [String: Any] {
            ["id": id, "nick": id == "PreviewUser" ? "ClassicFan" : id == "Writer" ? "Writer" : id == "Reader2" ? "ReaderTwo" : "ReaderOne", "about": "Offline profile fixture.", "avatar": ["s": "https://preview.invalid/avatar"], "cover_url": "https://preview.invalid/cover", "num": ["created": 44, "featured": 5, "subscribers": 2, "subscriptions": 3], "is_in_subscriptions": subscriptions.contains(id)]
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
    @MainActor static var mentionRequest = ""
    @MainActor static var bulkRequest = ""
    @MainActor static var attachmentReads = [String]()
    @MainActor static func makeApp() throws -> AppContext {
        let transport = PreviewTransport()
        let api = try APIClient(installation: String(repeating: "a", count: 64), userAgent: "Offline UI preview", store: PreviewStore(), transport: transport, publicPictureTransport: transport)
        return AppContext(previewAPI: api)
    }
    static let post = #"{"id":"PreviewPost","type":"picture","url":"https://preview.invalid/post","size":{"w":640,"h":760},"creator":{"id":"PreviewUser","nick":"ClassicFan","avatar":{"s":"https://preview.invalid/avatar"}},"num":{"smiles":128,"comments":3}}"#
    static var feed: String {
        let second = post.replacingOccurrences(of: "PreviewPost", with: "NextPost").replacingOccurrences(of: "ClassicFan", with: "NextFan")
        var first = ProcessInfo.processInfo.arguments.contains("--ui-tests-video")
            ? post.replacingOccurrences(of: "\"type\":\"picture\"", with: "\"type\":\"video\"")
                .replacingOccurrences(of: "https://preview.invalid/post", with: "https://preview.invalid/fixture-video.mp4")
                .replacingOccurrences(of: "\"h\":760", with: "\"h\":360") : post
        if ProcessInfo.processInfo.arguments.contains("--ui-tests-gif") {
            first = post.replacingOccurrences(of: "\"type\":\"picture\"", with: "\"type\":\"gif\"")
                .replacingOccurrences(of: "https://preview.invalid/post", with: "https://preview.invalid/fixture-animation.gif")
                .replacingOccurrences(of: "\"h\":760", with: "\"h\":640")
        }
        if ProcessInfo.processInfo.arguments.contains("--ui-tests-comment-other-owner") {
            first = first.replacingOccurrences(of: "PreviewUser", with: "OtherPostOwner")
        }
        return "{\"status\":200,\"data\":{\"content\":{\"items\":[\(first),\(second)],\"paging\":{\"hasNext\":false}}}}"
    }
    static var comments: String {
        if ProcessInfo.processInfo.arguments.contains("--ui-tests-attachment-cards") { return attachmentComments }
        return """
        {"status":200,"data":{"comments":{"items":[
          {"id":"PreviewComment1","user":{"id":"PreviewUser","nick":"ClassicFan","photo":{"thumb":{"small_url":"https://preview.invalid/avatar"}}},"date":1792418400,"text":"The classic look is coming back.","num":{"replies":2}},
          {"id":"PreviewComment2","creator":{"id":"AnotherUser","nick":"AnotherUser","avatar":{"s":"https://preview.invalid/avatar2"}},"date":1792418400,"text":"An attached post, right in the thread.","attachments":{"content":[\(post.replacingOccurrences(of: "\"type\":\"picture\"", with: "\"type\":\"pic\""))]}},
          {"id":"PreviewComment3","user":{"id":"Reader","nick":"Reader"},"text":"Same feed. Familiar controls.","num":{"replies":0}}
        ],"paging":{"hasNext":false}}}}
        """
    }
    static let attachmentComments = #"""
    {"status":200,"data":{"comments":{"items":[
      {"id":"Cards","user":{"id":"PreviewUser","nick":"ClassicFan"},"text":"","attachments":{"content":[
        {"id":"AttachedPic","type":"pic","state":"published","thumb":{"proportional_url":"https://preview.invalid/comment-comic","proportional_size":{"w":320,"h":800}}},
        {"id":"AttachedGIF","type":"gif","thumb":{"url":"https://preview.invalid/comment-gif"},"size":{"w":320,"h":320},"bg_color":"#112233"},
        {"id":"AttachedGone","state":"deleted","thumb":{"url":"https://preview.invalid/never-load"}},
        {"id":"AttachedVideo","type":"video_clip","thumb":{"url":"https://preview.invalid/failed-preview"},"size":{"w":400,"h":300}},
        {"id":"FifthMustNotAppear"}]}},
      {"id":"Withheld","user":{"id":"Reader1","nick":"ReaderOne"},"text":" ","attachments":{"content":[],"content_from_links":[]}},
      {"id":"Abused","state":"abused","user":{"id":"Reader2","nick":"ReaderTwo"},"text":"ReaderTwo hidden attachment","attachments":{"content":[{"id":"Suppressed","type":"pic","url":"https://preview.invalid/never-load"}],"mention_user":[{"user_id":"Reader2","nick":"ReaderTwo","start_index":0,"stop_index":8}]}}
    ],"paging":{"hasNext":false}}}}
    """#
    static let publicAttachmentPicture = #"""
    <script>window.__INITIAL_STATE__={"feed":{"items":[{"id":"AttachedPic","type":"picture","state":"published","url":"https://preview.invalid/recovered-picture","size":{"w":640,"h":760},"creator":{"id":"RecoveredAuthor","nick":"RecoveredAuthor"},"smiles":8,"comments":0}]}};window.unrelated='not executed';</script>
    """#
    static let replies = #"{"status":200,"data":{"comment":{"replies_count":2},"replies":{"items":[{"id":"PreviewReply1","user":{"id":"Reader1","nick":"ReaderOne"},"text":"Reply number one","root_comm_id":"PreviewComment1","parent_comm_id":"PreviewComment1","depth":1,"num":{"smiles":2}},{"id":"PreviewReply2","user":{"id":"Reader2","nick":"ReaderTwo"},"text":"Reply number two","root_comm_id":"PreviewComment1","parent_comm_id":"PreviewReply1","depth":2}],"paging":{"hasNext":false}}}}"#
    @MainActor static func image(_ url: URL) -> UIImage {
        if url.lastPathComponent == "comment-comic" {
            return UIGraphicsImageRenderer(size: CGSize(width: 320, height: 800)).image { _ in
                UIColor.red.setFill(); UIRectFill(CGRect(x: 0, y: 0, width: 320, height: 240))
                UIColor.blue.setFill(); UIRectFill(CGRect(x: 0, y: 240, width: 320, height: 320))
                UIColor.green.setFill(); UIRectFill(CGRect(x: 0, y: 560, width: 320, height: 240))
            }
        }
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
