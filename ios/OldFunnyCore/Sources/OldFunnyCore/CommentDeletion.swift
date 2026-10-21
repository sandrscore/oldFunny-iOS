import Foundation

/// Android's selection endpoint reports positional per-comment results. Only an
/// explicit empty responses array with a successful outer status acknowledges
/// the whole selection (revival.CommentDelete); absent receipts stay uncertain.
public struct CommentDeletionReceipt: Equatable, Sendable {
    public let acceptedIDs: [String], remainingIDs: [String]
    public static func selectionField(_ ids: [String]) throws -> String {
        guard !ids.isEmpty, Set(ids).count == ids.count,
              ids.allSatisfy({ Wire.validID($0) && $0 != "null" }) else { throw ClientError.invalidInput }
        return ids.joined(separator: ",")
    }
    public init(_ response: JSON, requested ids: [String]) throws {
        _ = try Self.selectionField(ids)
        guard let status = response["status"].number, status == floor(status), (200..<300).contains(status),
              case .array(let results) = response["data"]["responses"], results.count <= ids.count else { throw ClientError.malformedResponse }
        if results.isEmpty { acceptedIDs = ids; remainingIDs = []; return }
        var accepted = [String](), remaining = [String]()
        for (index, id) in ids.enumerated() {
            if index < results.count, let status = results[index]["status"].number,
               status == floor(status), (200..<300).contains(status) { accepted.append(id) }
            else { remaining.append(id) }
        }
        acceptedIDs = accepted; remainingIDs = remaining
    }
}
