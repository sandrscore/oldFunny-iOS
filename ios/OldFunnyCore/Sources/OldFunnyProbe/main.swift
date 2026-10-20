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
        guard CommandLine.arguments == [CommandLine.arguments[0], "--anonymous-read-only"] else {
            print("Usage: OldFunnyProbe --anonymous-read-only")
            print("Sends one anonymous Featured GET with a new diagnostic installation; no login, account lookup, social writes, or read acknowledgements.")
            return
        }
        let id = (UUID().uuidString + UUID().uuidString).replacingOccurrences(of: "-", with: "").lowercased()
        do {
            let client = try APIClient(installation: id,
                userAgent: "iFunny/4.6.8(4121) iPhone/27.0.1 (oldFunny; read-only protocol probe)", store: NoCredentialStore())
            let page = try await client.feed(.featured)
            let output: [String: Any] = ["request": "GET /v4/feeds/featured", "authenticated": false,
                "decoded_posts": page.posts.count, "continuation_present": page.paging.next != nil,
                "usable_media_count": page.posts.filter { $0.mediaURL != nil || $0.posterURL != nil }.count,
                "runtime_tested": false, "credentials_persisted": false]
            let data = try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys])
            print(String(decoding: data, as: UTF8.self))
        } catch {
            print("Anonymous probe failed: " + ((error as? ClientError)?.errorDescription ?? "local tool error"))
        }
    }
}
