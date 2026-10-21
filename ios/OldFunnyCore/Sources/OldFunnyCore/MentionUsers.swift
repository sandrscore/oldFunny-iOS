import Foundation

public struct MentionUser: Equatable, Sendable {
    public let id: String, nickname: String
    public let avatarURL: URL?
    public let mutual: Bool
    public init?(_ value: JSON) {
        guard let id = value["id"].string, (1...64).contains(id.utf8.count), Wire.validID(id),
              let nickname = value["nick"].string, (1...25).contains(nickname.utf16.count),
              nickname.unicodeScalars.allSatisfy({ scalar in
                  if scalar.value == 95 { return true }
                  switch scalar.properties.generalCategory {
                  case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
                       .decimalNumber, .letterNumber, .otherNumber: return true
                  default: return false
                  }
              }), !(value["is_deleted"].flag ?? false), !(value["is_banned"].flag ?? false), !(value["is_blocked"].flag ?? false) else { return nil }
        self.id = id; self.nickname = nickname
        let thumb = value["photo"]["thumb"]
        avatarURL = Wire.https(thumb["small_url"].string) ?? Wire.https(thumb["medium_url"].string)
            ?? Wire.https(thumb["large_url"].string) ?? Wire.https(value["avatar"]["s"].string)
        mutual = (value["is_in_subscriptions"].flag ?? false) && (value["is_in_subscribers"].flag ?? false)
    }
}
public struct MentionUserPage: Sendable {
    public let users: [MentionUser], paging: Paging
    public init(_ data: JSON) throws {
        guard case .array = data["users"]["items"], case .object = data["users"]["paging"] else { throw ClientError.malformedResponse }
        var ids = Set<String>()
        users = data["users"]["items"].items.compactMap(MentionUser.init).filter { ids.insert($0.id).inserted }
        paging = try Paging(data["users"]["paging"])
    }
}
