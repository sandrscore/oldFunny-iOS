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
    private var replyCount: Int { 2 + sentReplies.count - deleted.filter { $0.hasPrefix("PreviewReply") || $0.hasPrefix("FixtureSentReply") }.count }
    func send(_ request: URLRequest) async throws -> HTTPResult {
        let path = request.url?.path ?? "", method = request.httpMethod ?? "GET"
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
}

enum PreviewFixtures {
    @MainActor static func makeApp() throws -> AppContext {
        let api = try APIClient(installation: String(repeating: "a", count: 64), userAgent: "Offline UI preview", store: PreviewStore(), transport: PreviewTransport())
        return AppContext(previewAPI: api)
    }
    static let post = #"{"id":"PreviewPost","type":"picture","url":"https://preview.invalid/post","size":{"w":640,"h":760},"creator":{"id":"PreviewUser","nick":"ClassicFan","avatar":{"s":"https://preview.invalid/avatar"}},"num":{"smiles":128,"comments":3}}"#
    static var feed: String {
        let second = post.replacingOccurrences(of: "PreviewPost", with: "NextPost").replacingOccurrences(of: "ClassicFan", with: "NextFan")
        return "{\"status\":200,\"data\":{\"content\":{\"items\":[\(post),\(second)],\"paging\":{\"hasNext\":false}}}}"
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
