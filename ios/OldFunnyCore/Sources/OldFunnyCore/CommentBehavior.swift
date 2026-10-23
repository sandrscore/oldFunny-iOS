import Foundation

public enum CommentOption: String, Equatable, Sendable {
    case reply, profile, report, delete, remove
}

/// CommentsFragment's role-ordered dialog and AnswersFragment's depth override.
/// Layout/page constants come from the current Android reference's resources.
public enum CommentBehavior {
    public static let maximumReplyDepth = 30
    public static let pageSize = 40
    public static func options(authorID: String?, originalAuthorID: String?, accountID: String?,
                               depth: Int, inReplies: Bool) -> [CommentOption] {
        var options: [CommentOption]
        if let accountID, !accountID.isEmpty, authorID == accountID { options = [.reply, .delete] }
        else if let accountID, !accountID.isEmpty, originalAuthorID == accountID { options = [.reply, .report, .remove] }
        else { options = [.reply, .profile, .report] }
        if inReplies && depth >= maximumReplyDepth { options.removeAll { $0 == .reply } }
        return options
    }
    /// Android uses a row of dots before the avatar, rather than unbounded
    /// indentation: depth-1 capped at 10 (15 for smallest width >=600dp).
    public static func replyDots(depth: Int, shortestViewportSide: Double) -> Int {
        guard depth > 1 else { return 0 }
        return min(depth - 1, shortestViewportSide >= 600 ? 15 : 10)
    }
}
