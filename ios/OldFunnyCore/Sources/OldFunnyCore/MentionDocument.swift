import Foundation

public struct MentionSpan: Equatable, Sendable {
    public let userID: String, nickname: String
    public let start: Int, end: Int
    public var range: NSRange { NSRange(location: start, length: end - start) }
    public init(userID: String, nickname: String, start: Int, end: Int) {
        self.userID = userID; self.nickname = nickname; self.start = start; self.end = end
    }
}
public struct MentionToken: Equatable, Sendable {
    public let start: Int, end: Int, query: String
}

/// Android MentionDocument's identities and UTF-16 ranges. Typing a nickname
/// alone never attaches an identity. Editing inside a chosen name drops it.
public struct MentionDocument: Equatable, Sendable {
    public private(set) var text: String
    public private(set) var mentions: [MentionSpan]
    public init(text: String = "", mentions: [MentionSpan] = []) {
        self.text = text; self.mentions = Self.clean(text: text, mentions: mentions)
    }
    public init(text: String, data: JSON) { self.init(text: text, mentions: Self.parse(text: text, data: data)) }
    private static func valid(_ mention: MentionSpan, in text: String) -> Bool {
        let units = Array(text.utf16), nick = Array(mention.nickname.utf16)
        return (1...64).contains(mention.userID.utf8.count) && Wire.validID(mention.userID)
            && (1...25).contains(nick.count) && mention.start >= 0 && mention.end > mention.start && mention.end <= units.count
            && units[mention.start..<mention.end].elementsEqual(nick)
    }
    private static func clean(text: String, mentions: [MentionSpan]) -> [MentionSpan] {
        let sorted = mentions.enumerated().filter { valid($0.element, in: text) }.sorted {
            $0.element.start == $1.element.start ? $0.offset < $1.offset : $0.element.start < $1.element.start
        }
        var result = [MentionSpan](), end = -1
        for (_, mention) in sorted where mention.start >= end { result.append(mention); end = mention.end }
        return result
    }
    public static func parse(text: String, data: JSON) -> [MentionSpan] {
        var spans = [MentionSpan]()
        for item in data.items {
            guard let start = item["start_index"].number, let stop = item["stop_index"].number,
                  start.isFinite, stop.isFinite, start == floor(start), stop == floor(stop),
                  start >= 0, start <= stop, stop < Double(text.utf16.count) else { continue }
            spans.append(MentionSpan(userID: item["user_id"].string ?? "", nickname: item["nick"].string ?? "",
                start: Int(start), end: Int(stop) + 1))
        }
        return clean(text: text, mentions: spans)
    }
    /// UIKit's edit range is measured in UTF-16, as Android TextWatcher is.
    /// Invalid ranges leave both text and identity unchanged.
    @discardableResult public mutating func replace(_ range: NSRange, with replacement: String) -> Bool {
        let units = Array(text.utf16)
        guard range.location >= 0, range.location <= units.count, range.length >= 0,
              range.length <= units.count - range.location else { return false }
        let start = range.location, end = start + range.length
        func boundary(_ index: Int) -> Bool {
            index == 0 || index == units.count || !(0xdc00...0xdfff).contains(units[index])
        }
        guard boundary(start), boundary(end) else { return false }
        let added = Array(replacement.utf16)
        let updated = String(decoding: Array(units[..<start]) + added + Array(units[end...]), as: UTF16.self)
        var shifted = [MentionSpan]()
        for span in mentions {
            if span.end <= start { shifted.append(span) }
            else if span.start >= end {
                let delta = added.count - range.length
                shifted.append(MentionSpan(userID: span.userID, nickname: span.nickname, start: span.start + delta, end: span.end + delta))
            }
        }
        text = updated; mentions = Self.clean(text: text, mentions: shifted); return true
    }
    public mutating func add(userID: String, nickname: String, at start: Int) throws {
        guard start >= 0, start <= text.utf16.count else { throw ClientError.invalidInput }
        let span = MentionSpan(userID: userID, nickname: nickname, start: start, end: start + nickname.utf16.count)
        guard Self.valid(span, in: text), !mentions.contains(where: { $0.start < span.end && span.start < $0.end }) else { throw ClientError.invalidInput }
        mentions.append(span); mentions = Self.clean(text: text, mentions: mentions)
    }
    private static func word(_ unit: UInt16) -> Bool {
        if unit == 95 { return true }
        guard let scalar = Unicode.Scalar(unit) else { return false }
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter, .decimalNumber: return true
        default: return false
        }
    }
    private static func whitespace(_ unit: UInt16) -> Bool {
        if (9...13).contains(unit) || (28...31).contains(unit) { return true }
        guard unit != 0x00a0, unit != 0x2007, unit != 0x202f, let scalar = Unicode.Scalar(unit) else { return false }
        return [.spaceSeparator, .lineSeparator, .paragraphSeparator].contains(scalar.properties.generalCategory)
    }
    public func token(cursor: Int, selectionEnd: Int) -> MentionToken? {
        let units = Array(text.utf16)
        guard cursor >= 0, cursor == selectionEnd, cursor <= units.count else { return nil }
        var start = cursor
        while start > 0 && Self.word(units[start - 1]) { start -= 1 }
        guard start > 0, units[start - 1] == 64 else { return nil }; start -= 1
        guard start == 0 || Self.whitespace(units[start - 1]), cursor - start <= 26 else { return nil }
        var end = cursor
        while end < units.count && Self.word(units[end]) { end += 1 }
        guard !mentions.contains(where: { start < $0.end && end > $0.start }) else { return nil }
        return MentionToken(start: start, end: end, query: String(decoding: units[(start + 1)..<cursor], as: UTF16.self))
    }
    /// The chosen name replaces @query, including its suffix to the right of
    /// the cursor, then gains an identity; the literal @ is not submitted.
    @discardableResult public mutating func choose(_ token: MentionToken, userID: String, nickname: String, cursor: Int) throws -> Int {
        guard self.token(cursor: cursor, selectionEnd: cursor) == token,
              text.utf16.count - (token.end - token.start) + nickname.utf16.count + 1 <= 300 else { throw ClientError.invalidInput }
        var changed = self
        guard changed.replace(NSRange(location: token.start, length: token.end - token.start), with: nickname + " ") else { throw ClientError.invalidInput }
        try changed.add(userID: userID, nickname: nickname, at: token.start)
        self = changed; return token.start + nickname.utf16.count + 1
    }
    public static func asciiTrim(_ text: String) -> String {
        let units = Array(text.utf16); var start = 0, end = units.count
        while start < end && units[start] <= 32 { start += 1 }
        while end > start && units[end - 1] <= 32 { end -= 1 }
        return String(decoding: units[start..<end], as: UTF16.self)
    }
    public func data(for submitted: String? = nil) -> JSON {
        let submitted = submitted ?? text
        let originalUnits = Array(text.utf16), submittedUnits = Array(submitted.utf16)
        var shift = 0
        if !originalUnits.elementsEqual(submittedUnits) {
            guard Array(Self.asciiTrim(text).utf16).elementsEqual(submittedUnits) else { return .array([]) }
            while shift < originalUnits.count && originalUnits[shift] <= 32 { shift += 1 }
        }
        return .array(mentions.filter { $0.start >= shift && $0.end <= shift + submittedUnits.count && Self.valid($0, in: text) }.map {
            .object(["user_id": .string($0.userID), "nick": .string($0.nickname), "start_index": .number(Double($0.start - shift)), "stop_index": .number(Double($0.end - shift - 1))])
        })
    }
    public func wire(for submitted: String? = nil) -> String? {
        let submitted = submitted ?? text
        let spans = Self.parse(text: submitted, data: data(for: submitted))
        guard !spans.isEmpty else { return nil }
        return spans.map { "\($0.userID):\($0.start):\($0.end - 1)" }.joined(separator: ";")
    }
}
