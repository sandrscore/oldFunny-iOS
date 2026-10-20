// Included only in the separate simulator preview configuration. This code is
// absent from the Release IPA; it uses no real service, credential or session.
#if CLASSIC_UI_PREVIEW
import UIKit

private struct PreviewStore: CredentialStore {
    func read() throws -> Credential? { nil }
    func write(_ credential: Credential) throws { throw ClientError.invalidInput }
    func erase() throws {}
}

private struct PreviewTransport: HTTPTransport {
    func send(_ request: URLRequest) async throws -> HTTPResult {
        let value: String
        if request.url?.path.contains("comments") == true { value = PreviewFixtures.comments }
        else if request.url?.path.contains("feeds") == true || request.url?.path.contains("timelines") == true { value = PreviewFixtures.feed }
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
