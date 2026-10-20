import Foundation

/// Only the server-issued HTTPS challenge page may complete verification.
/// This policy handles navigation, not CAPTCHA solving or server acceptance.
public enum CaptchaPolicy {
    public enum Decision: Equatable, Sendable { case allowPage, resolved, block }

    public static func isChallenge(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.host?.lowercased() == "ifunny.co"
            && url.port == nil && url.user == nil && url.password == nil
            && url.path.hasPrefix("/captcha/")
    }

    public static func decide(destination: URL, source: URL?, sourceIsMainFrame: Bool,
                              targetIsMainFrame: Bool) -> Decision {
        if destination.absoluteString == "ifunny://captcha_resolved" {
            return sourceIsMainFrame && targetIsMainFrame && source.map(isChallenge) == true ? .resolved : .block
        }
        if !targetIsMainFrame, destination.absoluteString == "about:blank" { return .allowPage }
        // Providers can load HTTPS subframes, while the main page stays inside
        // the challenge. Never send custom schemes to another installed app.
        guard destination.scheme?.lowercased() == "https", destination.host != nil,
              destination.user == nil, destination.password == nil else { return .block }
        return !targetIsMainFrame || isChallenge(destination) ? .allowPage : .block
    }
}
