import UIKit

@MainActor
final class SearchHistoryStore {
    private let defaults: UserDefaults
    private let key = "oldFunny.mixedSearchRecents.v1"
    private(set) var history: RecentSearchHistory
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key), let restored = try? RecentSearchHistory(data: data) { history = restored }
        else {
            // Legacy stores have no comparable timestamps. Retain their own
            // order deterministically; preserve original keys as a backup.
            let users = (defaults.array(forKey: "oldFunny.profileAuthorRecents.v1") as? [[String: String]] ?? []).compactMap { item -> RecentSearchEntry? in
                guard let user = try? UserProfile(.object(["id": .string(item["id"] ?? ""), "nick": .string(item["nick"] ?? ""), "avatar": .object(["s": .string(item["avatar"] ?? "")])])) else { return nil }
                return RecentSearchEntry(user: user)
            }
            let tags = (defaults.stringArray(forKey: "oldFunny.profileTagRecents.v1") ?? []).compactMap { try? RecentSearchEntry(tag: $0) }
            history = RecentSearchHistory(users + tags)
            if let data = try? history.encoded { defaults.set(data, forKey: key) }
        }
    }
    func record(_ entry: RecentSearchEntry) { history.record(entry); persist() }
    func clear(_ kind: RecentSearchEntry.Kind? = nil) { history.clear(kind); persist() }
    private func persist() { if let data = try? history.encoded { defaults.set(data, forKey: key) } }
}
