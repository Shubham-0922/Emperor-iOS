import Foundation
#if canImport(Darwin)
import Observation
#endif

/// The Limitation Landmine Radar's form and its answer, and every sentence the page words from
/// them (`src/pages/LimitationRadarPage.jsx`). The audit itself is the server's; this carries the
/// profile table and the presentation only.
///
/// See `ChatViewModel` for why `@Observable` is Apple-only.
#if canImport(Darwin)
@Observable
#endif
@MainActor
final class LimitationRadarViewModel {

    enum Field: Equatable, Sendable { case causeOfAction, intendedFiling, mediationStart, mediationEnd }

    static let disclaimer =
        "A date computation against the Schedule to the Limitation Act, 1963 — not legal advice. Limitation turns on the cause of action as actually pleaded, and on facts such as acknowledgments, part payments and prior proceedings that this tool does not see. Have the position reviewed before you act on it."

    static let subtitle =
        "Establish whether the limitation period has shut, and by how much, before you invest in the draft."

    static let mediationExplanation =
        "Section 12A, Commercial Courts Act, 2015 — commercial disputes only. The time spent is excluded from limitation, up to five months."

    static let mediationEndHint =
        "Date of the Mediation Authority's report. If left blank, the five-month maximum or the filing date is used, whichever is earlier."

    static let filingHint = "The date you intend to file, or the date actually filed."

    static let emptyMessage =
        "Choose the nature of the suit, enter the date time began to run and the filing date. The audit states the article applied, the last day to file, and what can be done if that day has passed."

    static let unreachableMessage =
        "The limitation audit service could not be reached. Check your connection and try again."

    private(set) var profileKey = LimitationProfile.defaultKey
    var causeOfAction: Date?
    var intendedFiling: Date?
    var mediationStart: Date?
    var mediationEnd: Date?
    private(set) var isRunning = false
    private(set) var result: LimitationAudit?
    private(set) var errorMessage: String?

    private let service: any LimitationRadarProviding

    init(service: any LimitationRadarProviding) {
        self.service = service
    }

    // MARK: - Form

    var profile: LimitationProfile { LimitationProfile.profile(for: profileKey) }

    /// "Under Article 55: <runs from>", the hint under the first date.
    var causeHint: String { "Under \(profile.article): \(profile.runsFrom)" }

    func selectProfile(_ key: String) {
        profileKey = LimitationProfile.all.contains { $0.key == key } ? key : LimitationProfile.defaultKey
    }

    func clear(_ field: Field) {
        switch field {
        case .causeOfAction: causeOfAction = nil
        case .intendedFiling: intendedFiling = nil
        case .mediationStart: mediationStart = nil
        case .mediationEnd: mediationEnd = nil
        }
    }

    /// What the web says when a required date is missing, or `nil` when both are there.
    var missingMessage: String? {
        let missing = [
            causeOfAction == nil ? "date time began to run" : nil,
            intendedFiling == nil ? "filing date" : nil,
        ].compactMap { $0 }
        return missing.isEmpty ? nil : "Enter the \(missing.joined(separator: " and the "))."
    }

    /// The body that would be sent, or `nil` while a required date is missing.
    var request: LimitationAuditRequest? {
        guard let causeOfAction, let intendedFiling else { return nil }
        return LimitationAuditRequest(
            profile: profileKey,
            causeOfAction: WireDate.dayKey(causeOfAction),
            intendedFiling: WireDate.dayKey(intendedFiling),
            mediationStart: mediationStart.map(WireDate.dayKey),
            mediationEnd: mediationEnd.map(WireDate.dayKey))
    }

    // MARK: - Run

    func run() async {
        guard !isRunning else { return }
        guard let request else {
            result = nil
            errorMessage = missingMessage
            return
        }
        isRunning = true
        errorMessage = nil
        defer { isRunning = false }
        do {
            result = try await service.audit(request)
        } catch {
            result = nil
            errorMessage = Self.message(for: error)
        }
    }

    static func message(for error: Error) -> String {
        if case APIError.transport = error { return unreachableMessage }
        if let api = error as? APIError { return api.errorDescription ?? unreachableMessage }
        return unreachableMessage
    }

    // MARK: - Words

    var bannerTone: LimitationOutcome { result?.outcome ?? .barred }

    /// The line beside the status chip, in the page's three branches.
    var headline: String? {
        guard let r = result else { return nil }
        if r.reliesOnMediationExclusion {
            return "\(Self.days(r.daysOverdue)) late without the exclusion · \(Self.days(-r.adjustedDaysOverdue)) remaining with it"
        }
        if r.daysOverdue > 0 { return "\(Self.days(r.daysOverdue)) past the last day to file" }
        return "\(Self.days(-r.daysOverdue)) remaining"
    }

    var lastDayText: String? { result.map { Self.longDate($0.bareDeadline) } }

    /// The "Mediation excluded" value, or `nil` when no mediation was entered.
    var mediationText: String? {
        guard let m = result?.mediation else { return nil }
        if m.beganAfterExpiry { return "None — it began after the period had expired" }
        let note = m.capped ? ", capped at five months" : (m.endAssumed ? ", end date assumed" : "")
        return "\(Self.days(m.excludedDays)) (\(Self.longDate(m.start)) to \(Self.longDate(m.end))\(note))"
    }

    /// The "With the exclusion" value, shown only when the exclusion is worth days.
    var adjustedText: String? {
        guard let r = result, let m = r.mediation, m.excludedDays > 0 else { return nil }
        return Self.longDate(r.adjustedDeadline)
    }

    var steps: [String] { result?.curativeStrategies ?? [] }

    /// "n day" / "n days", as the page's `days`.
    nonisolated static func days(_ n: Int) -> String { "\(n) day\(n == 1 ? "" : "s")" }

    /// `YYYY-MM-DD` as "15 January 2026" (en-GB, UTC), as the page's `longDate`. An unparseable
    /// string is returned as it came.
    nonisolated static func longDate(_ iso: String) -> String {
        guard let date = parser.date(from: iso) else { return iso }
        return display.string(from: date)
    }

    nonisolated(unsafe) private static let parser: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    nonisolated(unsafe) private static let display: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMMM yyyy"
        f.locale = Locale(identifier: "en_GB")
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()
}
