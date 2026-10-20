import Foundation

public struct Post: Equatable, Sendable {
    public let id: String
    public let type: String
    public let authorID: String?
    public let author: String
    public let title: String
    public let body: String
    public let mediaURL: URL?
    public let posterURL: URL?
    public let width: Double
    public let height: Double
    public let smiles: Int
    public let comments: Int
    public let isSmiled: Bool
    public var isVideo: Bool { type == "video" || type == "text_video" || mediaURL?.pathExtension.lowercased() == "mp4" }
    public var isGIF: Bool { type == "gif" && !isVideo }

    public init(_ value: JSON) throws {
        id = try Wire.requireID(value["id"].string ?? "")
        guard value["state"].string != "deleted", value["state"].string != "banned" else { throw ClientError.invalidInput }
        type = value["type"].string ?? "unknown"
        let user = value["creator"]
        authorID = user["id"].string.flatMap { Wire.validID($0) ? $0 : nil }
        author = user["nick"].string ?? "iFunny"
        title = value["title"].string ?? ""
        body = value["description"].string ?? value["text"].string ?? ""
        mediaURL = Wire.https(value["url"].string)
        posterURL = Wire.https(value["video_clip"]["screen_url"].string)
            ?? Wire.https(value["thumb"]["proportional_url"].string)
            ?? Wire.https(value["thumb"]["p"].string)
            ?? Wire.https(value["thumb"]["large_url"].string)
            ?? Wire.https(value["thumb"]["l"].string)
        width = max(1, min(30000, value["size"]["w"].number ?? 640))
        height = max(1, min(100000, value["size"]["h"].number ?? 640))
        smiles = max(0, value["num"]["smiles"].integer ?? value["smiles"].integer ?? 0)
        comments = max(0, value["num"]["comments"].integer ?? value["comments"].integer ?? 0)
        isSmiled = value["is"]["smiled"].flag ?? value["is_smiled"].flag ?? false
    }
}

public struct Paging: Equatable, Sendable {
    public let next: String?
    public init(_ value: JSON) throws {
        let cursor = value["cursors"]["next"].string
        if let cursor, cursor.utf8.count > 8192 { throw ClientError.malformedResponse }
        next = value["hasNext"].flag == false ? nil : cursor.flatMap { $0.isEmpty ? nil : $0 }
    }
}

public struct PostPage: Sendable {
    public let posts: [Post]
    public let paging: Paging
    public init(_ data: JSON) throws {
        let content = data["content"]
        guard case .array = content["items"] else { throw ClientError.malformedResponse }
        var seen = Set<String>()
        posts = content["items"].items.compactMap { try? Post($0) }.filter { seen.insert($0.id).inserted }
        paging = try Paging(content["paging"])
    }
}

public struct Comment: Sendable {
    public let id: String, text: String, author: String
    public let attachments: [Post]
    public let replies: Int
    public init(_ value: JSON) throws {
        id = try Wire.requireID(value["id"].string ?? "")
        text = value["text"].string ?? ""
        author = value["user"]["nick"].string ?? value["creator"]["nick"].string ?? "iFunny"
        attachments = value["attachments"]["content"].items.compactMap { try? Post($0) }
        replies = max(0, value["num"]["replies"].integer ?? 0)
    }
}

public struct CommentPage: Sendable {
    public let comments: [Comment]
    public let paging: Paging
    public init(_ data: JSON, replies: Bool = false) throws {
        let root = data[replies ? "replies" : "comments"]
        guard case .array = root["items"] else { throw ClientError.malformedResponse }
        var seen = Set<String>()
        comments = root["items"].items.compactMap { try? Comment($0) }.filter { seen.insert($0.id).inserted }
        paging = try Paging(root["paging"])
    }
}

/// Preserves server order and prevents endless continuation on repeated cursors.
public struct FeedPages: Sendable {
    public private(set) var posts: [Post] = []
    public private(set) var next: String?
    private var cursors = Set<String>()
    public init() {}
    public mutating func apply(_ page: PostPage, replacing: Bool) {
        if replacing { posts = []; cursors = [] }
        var ids = Set(posts.map(\.id))
        posts += page.posts.filter { ids.insert($0.id).inserted }
        if let cursor = page.paging.next, cursors.insert(cursor).inserted { next = cursor }
        else { next = nil }
    }
}

public enum Feed: String, CaseIterable, Sendable {
    case featured, subscriptions
    public var title: String { self == .featured ? "Featured" : "Subscriptions" }
    public var path: String { self == .featured ? "feeds/featured" : "timelines/home" }
    public var source: String { self == .featured ? "feat" : "subs" }
}
