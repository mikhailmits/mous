import Foundation

/// A typed description that already appears in the loaded ledger becomes a
/// category, so the next coffee is tagged like the last one.
public enum RepeatCategory {
    /// Matches `CTGRY_NAME_MAX_LENGTH` on the API.
    public static let nameMaxLength = 30

    public static func normalized(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let folded = trimmed.lowercased()
        if folded.count <= nameMaxLength {
            return folded
        }
        return String(folded.prefix(nameMaxLength))
    }

    public static func displayName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if trimmed.count <= nameMaxLength {
            return trimmed
        }
        return String(trimmed.prefix(nameMaxLength))
    }

    /// True when this name already occurs at least once in `transactions`
    /// (the month list on screen). The line being typed is not in that list yet.
    public static func shouldPromote(description: String, among transactions: [Transaction]) -> Bool {
        let key = normalized(description)
        guard !key.isEmpty else { return false }
        return transactions.contains { normalized($0.description) == key }
    }

    public static func existingID(matching description: String, in categories: [Category]) -> Int? {
        let key = normalized(description)
        guard !key.isEmpty else { return nil }
        return categories.first { normalized($0.name) == key }?.id
    }
}
