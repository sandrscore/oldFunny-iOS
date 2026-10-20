import Foundation

/// Android GalleryFragment/f has three retained panels, not a pushed comments
/// screen. Positions are vertical: information / media / comments.
public enum ViewerPanel: String, Sendable { case information, media, comments }
public enum VerticalSwipe: Sendable { case up, down }

public enum ViewerInteraction {
    public static func destination(from panel: ViewerPanel, swipe: VerticalSwipe) -> ViewerPanel? {
        switch (panel, swipe) {
        case (.media, .up): return .comments
        case (.media, .down): return .information
        case (.comments, .down), (.information, .up): return .media
        default: return nil
        }
    }

    /// The Android detector uses a vertical first direction, a consistent fling
    /// direction, and >1500 physical pixels/second. UIKit supplies points.
    public static func accepts(dx: Double, dy: Double, vx: Double, vy: Double,
                               displayScale: Double, childCanScroll: Bool,
                               editing: Bool, touches: Int = 1) -> Bool {
        guard [dx, dy, vx, vy, displayScale].allSatisfy(\.isFinite),
              displayScale > 0, touches == 1, !editing, !childCanScroll,
              abs(dy) > abs(dx), abs(vy) > abs(vx), dy * vy > 0 else { return false }
        return abs(vy) * displayScale > 1500
    }
}

/// Drafts are retained while switching panels and while choosing an existing
/// post. A completion clears only the exact revision that was submitted.
public struct ReplyRecipient: Equatable, Sendable {
    public let commentID: String, nickname: String
    public init(_ comment: Comment) { commentID = comment.id; nickname = comment.author }
}

public struct CommentDraft: Equatable, Sendable {
    public private(set) var text = ""
    public private(set) var attachment: Post?
    public private(set) var recipient: ReplyRecipient?
    public private(set) var revision: UInt64 = 0
    public init() {}
    public var canSend: Bool {
        text.utf16.count <= 300 && (!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || attachment != nil)
    }
    public mutating func edit(_ value: String) { if text != value { text = value; revision &+= 1 } }
    public mutating func attach(_ post: Post?) { if attachment != post { attachment = post; revision &+= 1 } }
    public mutating func reply(to comment: Comment?) {
        let value = comment.map(ReplyRecipient.init)
        if recipient != value { recipient = value; revision &+= 1 }
    }
    public func replyParentID(root: String?) -> String? { recipient?.commentID ?? root }
    public mutating func clear(ifRevision submitted: UInt64) {
        guard revision == submitted else { return }; text = ""; attachment = nil; recipient = nil; revision &+= 1
    }
}
