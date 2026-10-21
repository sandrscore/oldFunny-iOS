import Foundation

/// Public profile fields only. Account email and registration data stay out of
/// profile UI, browser state and caches.
public struct UserProfile: Equatable, Sendable {
    public let id: String, nickname: String, about: String
    public let avatarURL: URL?, coverURL: URL?
    public let created: Int, featured: Int, subscribers: Int, subscriptions: Int
    public let isSubscribed: Bool, isBlocked: Bool, areYouBlocked: Bool, isDeleted: Bool
    public init(_ value: JSON) throws {
        id = try Wire.requireID(value["id"].string ?? "")
        nickname = value["nick"].string ?? "iFunny"; about = value["about"].string ?? ""
        avatarURL = Wire.https(value["avatar"]["s"].string)
            ?? Wire.https(value["photo"]["thumb"]["small_url"].string)
            ?? Wire.https(value["avatar"]["m"].string) ?? Wire.https(value["photo"]["url"].string)
        coverURL = Wire.https(value["cover_url"].string) ?? Wire.https(value["cover"]["url"].string)
        created = max(0, value["num"]["created"].integer ?? value["num"]["total_posts"].integer ?? value["total_posts"].integer ?? 0)
        featured = max(0, value["num"]["featured"].integer ?? 0)
        subscribers = max(0, value["num"]["subscribers"].integer ?? 0)
        subscriptions = max(0, value["num"]["subscriptions"].integer ?? 0)
        isSubscribed = value["is_in_subscriptions"].flag ?? false
        isBlocked = value["is_blocked"].flag ?? false; areYouBlocked = value["are_you_blocked"].flag ?? false
        isDeleted = (value["is_deleted"].flag ?? false) || (value["is_banned"].flag ?? false)
    }
}
public enum UserListKind: String, Sendable { case subscribers, subscriptions }
public struct UserPage: Sendable {
    public let users: [UserProfile], paging: Paging
    public init(_ data: JSON) throws {
        let list = data["users"]
        guard case .array = list["items"], case .object = list["paging"] else { throw ClientError.malformedResponse }
        var seen = Set<String>()
        users = list["items"].items.compactMap { try? UserProfile($0) }.filter { seen.insert($0.id).inserted }
        paging = try Paging(list["paging"])
    }
}
public enum ProfileMediaKind: String, CaseIterable, Sendable {
    case all, images, text, videos, gifs
    public var title: String {
        switch self { case .all: return "All media"; case .images: return "Images"; case .text: return "Text posts"; case .videos: return "Videos"; case .gifs: return "Animated GIFs" }
    }
    public static func category(_ type: String) -> Self? {
        switch type {
        case "pic", "text_pic", "caption", "mem", "dem", "comics", "old": return .images
        case "text_post": return .text
        case "video", "video_clip", "text_video", "coub", "vine": return .videos
        case "gif", "gif_caption", "text_gif": return .gifs
        default: return nil
        }
    }
}
/// ProfileSearchQuery semantics: all tags AND, original author identity, and a
/// repub toggle based on source presence rather than the viewer reaction flag.
public struct ProfileSearchCriteria: Equatable, Sendable {
    public var media: ProfileMediaKind = .all
    public var authorID: String?
    public var authorNickname = ""
    public var includeRepubs = true
    public private(set) var tags = Set<String>()
    public init() {}
    public static func normalized(_ text: String, prefix: Character = "#") -> String {
        var text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.first == prefix { text.removeFirst() }
        return text.lowercased(with: Locale(identifier: "en_US_POSIX"))
    }
    public mutating func setTags(_ value: [String]) { tags = Set(value.map { Self.normalized($0) }.filter { !$0.isEmpty }) }
    public func matches(_ post: Post, profileID: String) -> Bool {
        guard let category = ProfileMediaKind.category(post.type), media == .all || media == category else { return false }
        let originalID = post.hasSource ? post.originalAuthorID : post.authorID
        let originalName = post.hasSource ? post.originalAuthor : post.author
        if !includeRepubs {
            guard !post.hasSource, post.authorID == profileID else { return false }
        } else if let authorID {
            guard originalID == authorID else { return false }
        } else {
            let requested = Self.normalized(authorNickname, prefix: "@")
            guard requested.isEmpty || originalName.map({ Self.normalized($0, prefix: "@") }) == requested else { return false }
        }
        return Set(post.tags.map { Self.normalized($0) }).isSuperset(of: tags)
    }
}
public enum ProfileActionError: Error, Equatable, LocalizedError {
    case pinLimit, unconfirmed, cursorLoop
    public var errorDescription: String? {
        switch self {
        case .pinLimit: return "You can pin up to 3 posts. Unpin one first."
        case .unconfirmed: return "The change was not confirmed. Refresh this profile before trying again."
        case .cursorLoop: return "The server repeated a page cursor. Your loaded posts are retained."
        }
    }
}
/// Grid and swipe viewer share loaded order/cursor. Validate before mutation so
/// a malformed repeated page cannot poison retry or claim a false clean end.
public struct ProfilePages: Sendable {
    public private(set) var posts = [Post]()
    public private(set) var next: String?
    public private(set) var loaded = false
    private var cursors = Set<String>()
    public init() {}
    public mutating func apply(_ page: PostPage, replacing: Bool, featuredOwner: String? = nil) throws {
        if let cursor = page.paging.next, !replacing && (cursor == next || cursors.contains(cursor)) { throw ProfileActionError.cursorLoop }
        if replacing { posts = []; cursors = [] }
        var ids = Set(posts.map(\.id))
        posts += page.posts.filter {
            $0.state == "published" && !$0.isAbused && (featuredOwner == nil || ($0.authorID == featuredOwner && $0.isFeatured)) && ids.insert($0.id).inserted
        }
        next = page.paging.next; if let next { cursors.insert(next) }; loaded = true
    }
}
