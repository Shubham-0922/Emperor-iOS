import Foundation

/// The cases looked up lately on this device, newest first — a shortcut back, not a record
/// (`fetchOrdersApi.js` `readRecent` / `rememberCase`).
///
/// Kept per account in the response cache's store, so signing out — which clears that store —
/// forgets them with everything else the account left on the phone.
struct LookupHistory: Sendable {

    /// One remembered lookup: the card to send again, the record's title, and when.
    struct Entry: Codable, Equatable, Sendable, Identifiable {
        var key: String
        var card: CourtSearchResult
        var title: String
        /// ISO instant of the lookup.
        var at: String

        var id: String { key }

        /// The row's title: the cause title tidied, else the case number.
        var displayTitle: String {
            if !title.isEmpty { return CourtNames.tidy(title, title: true) }
            return "\(card.caseType ?? "") \(card.caseNumber ?? "")/\(card.caseYear ?? "")"
        }

        /// The row's second line: court · case · the day it was looked up.
        var detail: String {
            let number = "\(card.caseType ?? "") \(card.caseNumber ?? "")/\(card.caseYear ?? "")"
            let day = MatterRecord.fmtDay(String(at.prefix(10)))
            return "\(card.courtName ?? "") · \(number) · \(day)"
        }
    }

    /// How many are kept; the screen shows `shown` of them.
    static let limit = 6
    static let shown = 3

    let store: any CacheStore
    let userID: String
    /// Injected so a test can pin the stamp.
    var now: @Sendable () -> Date = { Date() }

    var storageKey: String { "fetch-orders-recent-\(userID)" }

    /// Newest first, at most `limit`.
    var entries: [Entry] {
        guard let data = store.read(storageKey),
              let list = try? JSONDecoder().decode([Entry].self, from: data)
        else { return [] }
        return Array(list.prefix(Self.limit))
    }

    /// Puts this case at the top, replacing an earlier lookup of the same case.
    @discardableResult
    func remember(_ card: CourtSearchResult, title: String?) -> [Entry] {
        let key = card.historyKey
        let rest = entries.filter { $0.key != key }
        let named = (title?.isEmpty == false) ? title! : (card.title ?? "")
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let stamp = formatter.string(from: now())
        let entry = Entry(key: key, card: card, title: named, at: stamp)
        let list = Array(([entry] + rest).prefix(Self.limit))
        if let data = try? JSONEncoder().encode(list) { store.write(data, for: storageKey) }
        return list
    }

    func clear() { store.remove(storageKey) }
}
