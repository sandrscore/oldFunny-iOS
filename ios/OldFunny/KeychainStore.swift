import Foundation
import Security

struct KeychainStore: CredentialStore {
    private static let service = "mobi.oldfunny.ios.session.v1"
    private static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account,
         kSecAttrSynchronizable as String: false]
    }
    private static func get(_ account: String) throws -> Data? {
        var query = query(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let result = result as? Data else { throw ClientError.transport }
        return result
    }
    private static func put(_ data: Data, account: String) throws {
        let base = query(account)
        let attrs: [String: Any] = [kSecValueData as String: data,
                                   kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(base as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound {
            var insert = base; attrs.forEach { insert[$0.key] = $0.value }
            guard SecItemAdd(insert as CFDictionary, nil) == errSecSuccess else { throw ClientError.transport }
        } else if status != errSecSuccess { throw ClientError.transport }
    }
    static func installation() throws -> String {
        if let data = try get("installation"), let value = String(data: data, encoding: .utf8) {
            _ = try Wire.basic(installation: value); return value
        }
        let value = (UUID().uuidString + UUID().uuidString).replacingOccurrences(of: "-", with: "").lowercased()
        try put(Data(value.utf8), account: "installation")
        return value
    }
    func read() throws -> Credential? {
        guard let data = try Self.get("credential") else { return nil }
        do { return try JSONDecoder().decode(Credential.self, from: data) }
        catch { throw ClientError.malformedResponse }
    }
    func write(_ credential: Credential) throws { try Self.put(JSONEncoder().encode(credential), account: "credential") }
    func erase() throws {
        let status = SecItemDelete(Self.query("credential") as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw ClientError.transport }
    }
}
