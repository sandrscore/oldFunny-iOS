import Foundation

/// The patched Android AttachmentSpec contract, independent of a full Post.
/// Unavailable and ID-less cards must survive decoding rather than disappearing.
public struct CommentAttachment: Equatable, Sendable {
    public let id: String, type: String, badge: String
    public let previewURL: URL?
    public let width: Int, height: Int
    public let backgroundARGB: UInt32
    public let unavailable: Bool
    public var contentID: String? { Wire.validID(id) ? id : nil }

    private init(_ value: JSON) {
        id = value["id"].string ?? ""; type = value["type"].string ?? ""
        let state = value["state"].string ?? ""
        unavailable = (!state.isEmpty && state != "published") || value["is_abused"].flag == true || value["creator"]["is_blocked"].flag == true
        let thumb = value["thumb"]
        var url = ["proportional_url", "large_url", "url", "proportional_webp_url", "large_webp_url", "webp_url"].compactMap { Self.webURL(thumb[$0].string) }.first
        if url == nil { url = Self.webURL(value["video_clip"]["screen_url"].string) }
        if url == nil && type == "pic" { url = Self.webURL(value["url"].string) }
        previewURL = unavailable ? nil : url
        let size: JSON
        if case .object(let fields) = thumb["proportional_size"], !fields.isEmpty { size = thumb["proportional_size"] }
        else { size = value["size"] }
        width = Self.dimension(size["w"]); height = Self.dimension(size["h"])
        badge = type.contains("gif") ? "GIF" : type.contains("video") || type == "coub" ? "VIDEO" : ""
        var hex = value["bg_color"].string ?? ""; if hex.hasPrefix("#") { hex.removeFirst() }
        if [6, 8].contains(hex.utf8.count), hex.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }), let number = UInt32(hex, radix: 16) {
            backgroundARGB = hex.count == 6 ? 0xff000000 | number : number
        } else { backgroundARGB = 0xff333337 }
    }
    private static func dimension(_ value: JSON) -> Int {
        guard case .number(let number) = value else { return 320 }
        if number.isNaN || number < 1 { return 1 }; if number > 10000 { return 10000 }; return Int(number)
    }
    public static func webURL(_ value: String?) -> URL? {
        // Foundation can repair spaces and malformed percent escapes that
        // Android's java.net.URI rejects. Preserve that validation boundary.
        guard let value, !value.unicodeScalars.contains(where: { $0.value <= 32 || $0.value == 127 || "<>\"{}|\\^`".unicodeScalars.contains($0) }) else { return nil }
        let bytes = Array(value.utf8)
        func hex(_ byte: UInt8) -> Bool { (48...57).contains(byte) || (65...70).contains(byte) || (97...102).contains(byte) }
        for i in bytes.indices where bytes[i] == 37 {
            guard i + 2 < bytes.count, hex(bytes[i + 1]), hex(bytes[i + 2]) else { return nil }
        }
        guard let url = URL(string: value), let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http", url.host != nil, url.user == nil, url.password == nil else { return nil }
        return url
    }
    public static func parse(_ attachments: JSON) -> [Self] {
        func collect(_ rows: JSON) -> [Self] {
            var result = [Self]()
            for row in rows.items {
                guard case .object = row else { continue }; let item = Self(row)
                if !item.id.isEmpty || item.previewURL != nil { result.append(item) }
                if result.count == 4 { break }
            }
            return result
        }
        let primary = collect(attachments["content"])
        return primary.isEmpty ? collect(attachments["content_from_links"]) : primary
    }
    public static func isWithheld(_ attachments: JSON) -> Bool {
        guard case .array = attachments["content"], case .object(let fields) = attachments else { return false }
        return fields.values.allSatisfy { if case .array(let items) = $0 { return items.isEmpty }; return false }
    }
}

public struct PreviewSize: Equatable, Sendable {
    public let width: Int, height: Int
}
public struct PreviewRect: Equatable, Sendable {
    public let left: Int, top: Int, right: Int, bottom: Int
}
/// Float arithmetic/rounding and integer crop edges mirror revival.PreviewCrop.
public enum CommentPreviewCrop {
    public static func size(imageWidth: Int, imageHeight: Int, maxWidth: Int, minHeight: Int) throws -> PreviewSize {
        guard imageWidth > 0, imageHeight > 0, maxWidth > 0, minHeight >= 0,
              [imageWidth, imageHeight, maxWidth, minHeight].allSatisfy({ $0 <= Int32.max }) else { throw ClientError.invalidInput }
        let ratio = min(Float(4) / 3, Float(imageHeight) / Float(imageWidth))
        let maxHeight = max(1, Int((Float(maxWidth) * 3 / 4).rounded()))
        let height = max(min(minHeight, maxHeight), min(maxHeight, max(1, Int((Float(maxWidth) * ratio).rounded()))))
        return PreviewSize(width: min(maxWidth, max(1, Int((Float(height) / ratio).rounded()))), height: height)
    }
    public static func source(imageWidth: Int, imageHeight: Int, width: Int, height: Int, fromTop: Bool) throws -> PreviewRect {
        guard [imageWidth, imageHeight, width, height].allSatisfy({ $0 > 0 && $0 <= Int32.max }) else { throw ClientError.invalidInput }
        var cropWidth = imageWidth, cropHeight = imageHeight
        if imageWidth * height > imageHeight * width { cropWidth = max(1, imageHeight * width / height) }
        else { cropHeight = max(1, imageWidth * height / width) }
        let left = (imageWidth - cropWidth) / 2, top = fromTop ? 0 : (imageHeight - cropHeight) / 2
        return PreviewRect(left: left, top: top, right: left + cropWidth, bottom: top + cropHeight)
    }
}
