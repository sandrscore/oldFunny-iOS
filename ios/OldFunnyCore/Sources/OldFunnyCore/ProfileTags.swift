import Foundation

/// Limits from Android tags.xml, reused by ProfileSearchTagsActivity. The
/// search criteria itself remains a set; the editor retains insertion order.
public struct ProfileTagSelection: Equatable, Sendable {
    public private(set) var tags = [String]()
    public static let limit = 5
    public init(_ values: [String] = []) { for value in values { _ = add(value) } }
    public static func valid(_ text: String) -> String? {
        let text = ProfileSearchCriteria.normalized(text)
        guard (2...100).contains(text.utf16.count), text.unicodeScalars.allSatisfy({ scalar in
            // Android checks UTF-16 chars, so supplementary symbols fail its
            // input filter. Keep letters/marks/numbers/connectors and enclosed
            // alphanumeric symbols from the original tag group filter.
            guard scalar.value <= 0xffff else { return false }
            switch scalar.properties.generalCategory {
            case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
                 .nonspacingMark, .spacingMark, .enclosingMark, .decimalNumber, .letterNumber, .connectorPunctuation: return true
            case .otherSymbol: return (0x2460...0x24ff).contains(scalar.value)
            default: return false
            }
        }) else { return nil }
        return text
    }
    @discardableResult public mutating func add(_ value: String) -> Bool {
        guard let tag = Self.valid(value) else { return false }
        if tags.contains(tag) { return true }
        guard tags.count < Self.limit else { return false }
        tags.append(tag); return true
    }
    public mutating func remove(_ value: String) { tags.removeAll { $0 == value } }
}

public struct SuggestedTags: Sendable {
    public let tags: [String]
    public init(_ data: JSON) throws {
        guard case .array = data["tags"]["items"] else { throw ClientError.malformedResponse }
        var seen = Set<String>()
        tags = data["tags"]["items"].items.compactMap { $0["tag"].string.flatMap(ProfileTagSelection.valid) }
            .filter { seen.insert($0).inserted }
    }
}
