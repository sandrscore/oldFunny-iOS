import Foundation
import OldFunnyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private actor ContentReadAudit: HTTPTransport {
    private let base: any HTTPTransport
    private let host: String, path: String
    private var statuses = [Int]()
    init(base: any HTTPTransport, host: String, path: String) { self.base = base; self.host = host; self.path = path }
    func send(_ request: URLRequest) async throws -> HTTPResult {
        guard request.httpMethod == "GET", request.url?.host == host, request.url?.path == path, statuses.count < 1 else { throw ClientError.invalidInput }
        let response = try await base.send(request); statuses.append(response.status); return response
    }
    func recorded() -> [Int] { statuses }
}

private struct NoCredentialStore: CredentialStore {
    func read() throws -> Credential? { nil }
    func write(_ credential: Credential) throws { throw ClientError.invalidInput }
    func erase() throws {}
}

private actor ExploreReadAudit: HTTPTransport {
    private let base = URLTransport()
    private var paths = Set<String>(), statuses = [String: Int]()
    func send(_ request: URLRequest) async throws -> HTTPResult {
        let path = request.url?.path ?? ""
        guard request.httpMethod == "GET", request.url?.host == "api.ifnapp.com",
              ["/v4/tags/explore", "/v4/tags/suggested", "/v4/search/content"].contains(path),
              request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Basic ") == true,
              paths.insert(path).inserted else { throw ClientError.invalidInput }
        let result = try await base.send(request); statuses[path] = result.status; return result
    }
    func recorded() -> [String: Int] { statuses }
}

@main
struct Probe {
    static func main() async {
        let profiles = CommandLine.arguments == [CommandLine.arguments[0], "--anonymous-profile-read-only"]
        let explore = CommandLine.arguments == [CommandLine.arguments[0], "--anonymous-explore-read-only"]
        let contentID = CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--anonymous-content-read-only" ? CommandLine.arguments[2] : nil
        guard profiles || explore || contentID != nil || CommandLine.arguments == [CommandLine.arguments[0], "--anonymous-read-only"] else {
            print("Usage: OldFunnyProbe --anonymous-read-only | --anonymous-profile-read-only | --anonymous-content-read-only ID | --anonymous-explore-read-only")
            print("Sends one anonymous Featured GET with a new diagnostic installation; no login, account lookup, social writes, or read acknowledgements.")
            print("Profile mode additionally reads one public creator profile, its first timeline/featured pages, and a tag suggestion. Outputs counts/flags only; never authenticates or writes.")
            return
        }
        let id = (UUID().uuidString + UUID().uuidString).replacingOccurrences(of: "-", with: "").lowercased()
        do {
            if explore {
                let audit = ExploreReadAudit()
                let client = try APIClient(installation: id, userAgent: Wire.apiUserAgent(systemVersion: "27.0.1", model: "iPhone"), store: NoCredentialStore(), transport: audit)
                var output: [String: Any] = ["authenticated": false, "credentials_persisted": false, "social_writes": false, "read_acknowledgements": false, "runtime_tested": false]
                do { let page = try await client.explore(); output["explore"] = ["tags": page.tiles.count, "previews": page.tiles.filter { $0.previewURL != nil }.count] }
                catch { output["explore_error"] = (error as? ClientError)?.errorDescription ?? "local tool error" }
                do { let page = try await client.exploreTags("ca"); output["suggestions"] = ["tags": page.tiles.count] }
                catch { output["suggestions_error"] = (error as? ClientError)?.errorDescription ?? "local tool error" }
                do { let page = try await client.tagFeed(TagFeed(tag: "cats")); output["tag_feed"] = ["posts": page.posts.count, "continuation": page.paging.next != nil] }
                catch { output["tag_feed_error"] = (error as? ClientError)?.errorDescription ?? "local tool error" }
                output["statuses"] = await audit.recorded()
                print(String(decoding: try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys]), as: UTF8.self)); return
            }
            if let contentID {
                guard Wire.validID(contentID), contentID.utf8.count <= 40 else { throw ClientError.invalidInput }
                let api = ContentReadAudit(base: URLTransport(), host: "api.ifnapp.com", path: "/v4/content/" + contentID)
                let website = ContentReadAudit(base: PublicPictureTransport(), host: "ifunny.co", path: "/picture/" + contentID)
                let client = try APIClient(installation: id, userAgent: Wire.apiUserAgent(systemVersion: "27.0.1", model: "iPhone"),
                                           store: NoCredentialStore(), transport: api, publicPictureTransport: website)
                var output: [String: Any] = ["authenticated": false, "credentials_persisted": false, "social_writes": false, "runtime_tested": false]
                do {
                    let post = try await client.content(postID: contentID)
                    output["decoded"] = true; output["identity_matches"] = post.id == contentID
                    output["media_present"] = post.mediaURL != nil; output["poster_present"] = post.posterURL != nil
                    output["type"] = post.type; output["width"] = post.width; output["height"] = post.height
                } catch { output["error"] = (error as? ClientError)?.errorDescription ?? "local tool error" }
                output["api_statuses"] = await api.recorded(); output["website_statuses"] = await website.recorded()
                print(String(decoding: try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys]), as: UTF8.self)); return
            }
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
