import Foundation
import Photos

enum PhotoExporter {
    static func save(_ post: Post, loader: MediaLoader) async -> String {
        let permission = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard permission == .authorized || permission == .limited else { return "Allow oldFunny to add photos in iOS Settings, then try Save again." }
        do {
            let file = try await loader.exportFile(post)
            defer { try? FileManager.default.removeItem(at: file) }
            try Task.checkCancellation()
            try await PHPhotoLibrary.shared().performChanges {
                let asset = PHAssetCreationRequest.forAsset()
                asset.addResource(with: post.isVideo ? .video : .photo, fileURL: file, options: nil)
            }
            return post.isVideo ? "Video saved." : "Image saved."
        } catch { return "Could not save this media. Check your connection and available storage, then try again." }
    }
}
