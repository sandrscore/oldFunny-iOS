import UIKit

/// One ordered snapshot/cursor shared by a grid and its retained swipe viewer.
@MainActor
protocol PostGallerySource: AnyObject {
    var app: AppContext { get }
    var nickname: String { get }
    var postSource: String { get }
    var profileOwnerID: String? { get }
    var galleryIdentifier: String { get }
    var posts: [Post] { get }
    var loading: Bool { get }
    var loaded: Bool { get }
    var error: Error? { get }
    var onViewerUpdate: (() -> Void)? { get set }
    func setActive(_ value: Bool, consumeRefresh: Bool)
    func retry()
    func loadNext()
    func pinsChanged()
}
extension ProfileBrowser: PostGallerySource {
    var postSource: String { "prof" }
    var profileOwnerID: String? { userID }
    var galleryIdentifier: String { "profile-gallery" }
    func pinsChanged() { needsRefresh = true }
}
