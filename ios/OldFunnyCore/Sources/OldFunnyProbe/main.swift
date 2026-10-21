import Foundation
import OldFunnyCore

private struct NoCredentialStore: CredentialStore {
    func read() throws -> Credential? { nil }
    func write(_ credential: Credential) throws { throw ClientError.invalidInput }
    func erase() throws {}
}

@main
struct Probe {
    static func main() async {
        let profiles = CommandLine.arguments == [CommandLine.arguments[0], "--anonymous-profile-read-only"]
        guard profiles || CommandLine.arguments == [CommandLine.arguments[0], "--anonymous-read-only"] else {
            print("Usage: OldFunnyProbe --anonymous-read-only | --anonymous-profile-read-only")
            print("Sends one anonymous Featured GET with a new diagnostic installation; no login, account lookup, social writes, or read acknowledgements.")
            print("Profile mode additionally reads one public creator profile, its first timeline/featured pages, and a tag suggestion. Outputs counts/flags only; never authenticates or writes.")
            return
        }
        let id = (UUID().uuidString + UUID().uuidString).replacingOccurrences(of: "-", with: "").lowercased()
        do {
            let client = try APIClient(installation: id,
                userAgent: Wire.apiUserAgent(systemVersion: "27.0.1", model: "iPhone"), store: NoCredentialStore())
            let page = try await client.feed(.featured)
            var output: [String: Any] = ["request": "GET /v4/feeds/featured", "authenticated": false,
                "decoded_posts": page.posts.count, "continuation_present": page.paging.next != nil,
                "usable_media_count": page.posts.filter { $0.mediaURL != nil || $0.posterURL != nil }.count,
                "runtime_tested": false, "credentials_persisted": false]
            if profiles, let owner = page.posts.compactMap(\.authorID).first {
                func safeError(_ error: Error) -> String { (error as? ClientError)?.errorDescription ?? "local tool error" }
                do {
                    let user = try await client.profile(userID: owner)
                    output["public_profile"] = ["decoded": true, "identity_matches": user.id == owner, "created_count": user.created,
                        "featured_count": user.featured, "avatar_present": user.avatarURL != nil, "cover_present": user.coverURL != nil]
                } catch { output["public_profile_error"] = safeError(error) }
                do { let timeline = try await client.profileTimeline(userID: owner); output["profile_timeline"] = ["posts": timeline.posts.count, "continuation_present": timeline.paging.next != nil] }
                catch { output["profile_timeline_error"] = safeError(error) }
                do { let timeline = try await client.profileTimeline(userID: owner, featured: true)
                    output["profile_featured"] = ["posts": timeline.posts.count, "owner_matches": timeline.posts.filter { $0.authorID == owner }.count, "featured_flags": timeline.posts.filter(\.isFeatured).count, "continuation_present": timeline.paging.next != nil]
                } catch { output["profile_featured_error"] = safeError(error) }
                do { let tags = try await client.suggestedTags("ca"); output["suggested_tags"] = ["decoded": true, "count": tags.tags.count] }
                catch { output["suggested_tags_error"] = safeError(error) }
            }
            let data = try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys])
            print(String(decoding: data, as: UTF8.self))
        } catch {
            print("Anonymous probe failed: " + ((error as? ClientError)?.errorDescription ?? "local tool error"))
        }
    }
}
