import Foundation

/// Preserve the server's exact tag. Editor normalization is a different policy.
public enum ExploreTag {
    public static func valid(_ value: String) -> Bool {
        !value.isEmpty && value.utf16.count <= 100 && !value.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }
    public static func require(_ value: String) throws -> String {
        guard valid(value) else { throw ClientError.invalidInput }; return value
    }
}
public struct ExploreTile: Equatable, Sendable {
    public let tag: String, uses: Int
    public let previewURL: URL?
    public init(_ value: JSON) throws {
        tag = try ExploreTag.require(value["tag"].string ?? "")
        uses = max(0, value["uses"].integer ?? 0)
        let content = value["content"]
        previewURL = Wire.https(content["thumb"]["large_url"].string)
            ?? Wire.https(content["thumb"]["l"].string)
            ?? Wire.https(content["thumb"]["small_url"].string)
            ?? Wire.https(content["thumb"]["s"].string) ?? Wire.https(content["url"].string)
    }
}
public struct ExplorePage: Sendable {
    public let tiles: [ExploreTile]
    public init(_ data: JSON) throws {
        guard case .array = data["tags"]["items"] else { throw ClientError.malformedResponse }
        var seen = Set<String>()
        tiles = data["tags"]["items"].items.compactMap { try? ExploreTile($0) }.filter { seen.insert($0.tag).inserted }
    }
}
public struct TagFeed: Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case tag, trending, channel }
    public let tag: String, kind: Kind
    public init(tag: String, kind: Kind = .tag) throws { self.tag = try ExploreTag.require(tag); self.kind = kind }
    public var path: String { kind == .channel ? "channels" : "search/content" }
    public var source: String { kind.rawValue + ":" + tag }
    public static func validSource(_ source: String) -> Bool {
        guard let colon = source.firstIndex(of: ":"), Kind(rawValue: String(source[..<colon])) != nil else { return false }
        return ExploreTag.valid(String(source[source.index(after: colon)...]))
    }
}

public struct RecentSearchEntry: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case user, tag }
    public let kind: Kind, query: String
    public let userID: String?, avatar: String?
    public init(tag: String) throws { kind = .tag; query = try ExploreTag.require(tag); userID = nil; avatar = nil }
    public init(user: UserProfile) { kind = .user; query = user.nickname; userID = user.id; avatar = user.avatarURL?.absoluteString }
    public var user: UserProfile? {
        guard kind == .user, let userID else { return nil }
        return try? UserProfile(.object(["id": .string(userID), "nick": .string(query), "avatar": .object(["s": .string(avatar ?? "")])]))
    }
    public var valid: Bool {
        if kind == .tag { return ExploreTag.valid(query) && userID == nil && avatar == nil }
        return !query.isEmpty && query.utf16.count <= 1024 && user != nil && (avatar == nil || Wire.https(avatar) != nil)
    }
}
/// RecentSearchHelper: exact query+type identity, newest first, ten mixed rows.
public struct RecentSearchHistory: Equatable, Sendable {
    public static let limit = 10
    public private(set) var entries = [RecentSearchEntry]()
    public init(_ values: [RecentSearchEntry] = []) {
        for value in values.reversed() { record(value) }
    }
    public init(data: Data) throws {
        guard data.count <= 64 * 1024 else { throw ClientError.malformedResponse }
        self.init(try JSONDecoder().decode([RecentSearchEntry].self, from: data))
    }
    public var encoded: Data { get throws { try JSONEncoder().encode(entries) } }
    public mutating func record(_ entry: RecentSearchEntry) {
        guard entry.valid else { return }
        entries.removeAll { $0.kind == entry.kind && $0.query == entry.query }
        entries.insert(entry, at: 0)
        if entries.count > Self.limit { entries.removeLast(entries.count - Self.limit) }
    }
    public mutating func clear(_ kind: RecentSearchEntry.Kind? = nil) {
        if let kind { entries.removeAll { $0.kind == kind } } else { entries.removeAll() }
    }
}
