import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum ClientError: Error, Equatable, LocalizedError {
    case invalidInput, malformedResponse, sessionChanged, signInRequired, transport
    case http(Int), network(Int), captcha(URL), unsupportedMedia

    /// Keep only a numeric Foundation error code, never its URL, body or userInfo.
    public static func networkFailure(_ error: Error) -> ClientError {
        if let error = error as? URLError { return .network(error.code.rawValue) }
        return .transport
    }

    public var errorDescription: String? {
        switch self {
        case .invalidInput: return "Please check your input."
        case .malformedResponse: return "iFunny returned an unreadable response."
        case .sessionChanged: return "Your account changed. Please refresh."
        case .signInRequired: return "Please sign in to continue."
        case .transport: return "Could not connect. Please try again."
        case .network(let code):
            let reason: String
            switch URLError.Code(rawValue: code) {
            case .notConnectedToInternet: reason = "The internet connection is offline."
            case .cannotFindHost, .dnsLookupFailed: reason = "Could not resolve iFunny’s server."
            case .cannotConnectToHost: reason = "Could not reach iFunny’s server."
            case .networkConnectionLost: reason = "The server connection was closed."
            case .timedOut: reason = "The connection timed out."
            case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
                 .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid:
                reason = "Could not establish a secure connection."
            case .dataNotAllowed: reason = "Network access is disabled for this app."
            default: reason = "Could not connect."
            }
            return "\(reason) (Network \(code).) Please try again."
        case .http(let status): return "iFunny returned HTTP \(status). Please try again."
        case .captcha: return "iFunny requires verification before you can sign in."
        case .unsupportedMedia: return "This media format is not supported yet."
        }
    }
}

/// The app never includes raw responses or credentials in an error description.
public enum JSON: Decodable, Equatable, Sendable {
    case object([String: JSON]), array([JSON]), string(String), number(Double), bool(Bool), null
    public init(from decoder: Decoder) throws {
        let box = try decoder.singleValueContainer()
        if box.decodeNil() { self = .null }
        else if let v = try? box.decode(Bool.self) { self = .bool(v) }
        else if let v = try? box.decode(String.self) { self = .string(v) }
        else if let v = try? box.decode(Double.self) { self = .number(v) }
        else if let v = try? box.decode([String: JSON].self) { self = .object(v) }
        else { self = .array(try box.decode([JSON].self)) }
    }
    public subscript(_ key: String) -> JSON {
        if case .object(let values) = self { return values[key] ?? .null }; return .null
    }
    public var string: String? { if case .string(let v) = self { return v }; return nil }
    public var items: [JSON] { if case .array(let v) = self { return v }; return [] }
    public var flag: Bool? { if case .bool(let v) = self { return v }; return nil }
    public var number: Double? {
        if case .number(let v) = self { return v }
        if let value = string { return Double(value) }; return nil
    }
    public var integer: Int? {
        guard let n = number, n.isFinite, n >= Double(Int.min), n < Double(Int.max) else { return nil }
        return Int(n)
    }
    public static func decode(_ data: Data) throws -> JSON {
        guard data.count <= 8 * 1024 * 1024, let value = try? JSONDecoder().decode(JSON.self, from: data) else {
            throw ClientError.malformedResponse
        }
        return value
    }
}

public enum Wire {
    public static let base = URL(string: "https://api.ifnapp.com/v4/")!
    /// Server-facing protocol profile observed in the modern iOS app. The app's
    /// own version is in Info.plist; classic 4.6.8 requests are disconnected by
    /// the current service even with an otherwise valid public Basic signature.
    public static func apiUserAgent(systemVersion: String, model: String) -> String {
        "iFunny/10.45.1(25370) iPhone/\(systemVersion) (Apple; \(model))"
    }
    // Public application client identifiers, not a user's Apple/iFunny credentials.
    // Provenance: docs/organic-login.md and android-diagnostics/revival/OrganicLoginProbe.java.
    public static let client = "JuiUH&3822"
    public static let salt = "HuUIC(ZQ918lkl*7"

    public static func validID(_ id: String) -> Bool {
        !id.isEmpty && id.utf8.count <= 64 && id.utf8.allSatisfy {
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0)
        }
    }
    public static func requireID(_ id: String) throws -> String {
        guard validID(id) else { throw ClientError.invalidInput }; return id
    }
    public static func https(_ string: String?) -> URL? {
        guard let string, let url = URL(string: string), url.scheme?.lowercased() == "https",
              url.host != nil, url.user == nil, url.password == nil else { return nil }
        return url
    }
    public static func captcha(_ value: JSON) -> URL? {
        guard value["error"].string == "captcha_required",
              let url = https(value["data"]["captcha_url"].string),
              url.host?.lowercased() == "ifunny.co", url.port == nil,
              url.path.hasPrefix("/captcha/") else { return nil }
        return url
    }
    public static func form(_ fields: [(String, String)]) -> Data {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        func encode(_ text: String) -> String {
            text.addingPercentEncoding(withAllowedCharacters: allowed)!.replacingOccurrences(of: "%20", with: "+")
        }
        return Data(fields.map { encode($0.0) + "=" + encode($0.1) }.joined(separator: "&").utf8)
    }
    public static func basic(installation: String) throws -> String {
        guard installation.utf8.count == 64, installation.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            throw ClientError.invalidInput
        }
        let digest = SHA1.hex(Data("\(installation):\(client):\(salt)".utf8))
        return "Basic " + Data("\(installation)_\(client):\(digest)".utf8).base64EncodedString()
    }
}

/// SHA-1 is required by the existing API's legacy app-client protocol, not used
/// for password storage, TLS, package integrity, or new cryptographic designs.
public enum SHA1 {
    public static func hex(_ data: Data) -> String {
        var bytes = [UInt8](data)
        let bitCount = UInt64(bytes.count) * 8
        bytes.append(0x80)
        while bytes.count % 64 != 56 { bytes.append(0) }
        bytes += (0..<8).reversed().map { UInt8(truncatingIfNeeded: bitCount >> ($0 * 8)) }
        var h: [UInt32] = [0x67452301, 0xefcdab89, 0x98badcfe, 0x10325476, 0xc3d2e1f0]
        func rol(_ value: UInt32, _ n: UInt32) -> UInt32 { (value << n) | (value >> (32 - n)) }
        for start in stride(from: 0, to: bytes.count, by: 64) {
            var w = [UInt32](repeating: 0, count: 80)
            for i in 0..<16 {
                let p = start + i * 4
                w[i] = UInt32(bytes[p]) << 24 | UInt32(bytes[p+1]) << 16 | UInt32(bytes[p+2]) << 8 | UInt32(bytes[p+3])
            }
            for i in 16..<80 { w[i] = rol(w[i-3] ^ w[i-8] ^ w[i-14] ^ w[i-16], 1) }
            var a = h[0], b = h[1], c = h[2], d = h[3], e = h[4]
            for i in 0..<80 {
                let f: UInt32, k: UInt32
                switch i {
                case 0..<20: f = (b & c) | (~b & d); k = 0x5a827999
                case 20..<40: f = b ^ c ^ d; k = 0x6ed9eba1
                case 40..<60: f = (b & c) | (b & d) | (c & d); k = 0x8f1bbcdc
                default: f = b ^ c ^ d; k = 0xca62c1d6
                }
                let next = rol(a, 5) &+ f &+ e &+ k &+ w[i]
                e = d; d = c; c = rol(b, 30); b = a; a = next
            }
            for (i, value) in [a,b,c,d,e].enumerated() { h[i] = h[i] &+ value }
        }
        return h.map { String(format: "%08x", $0) }.joined()
    }
}
