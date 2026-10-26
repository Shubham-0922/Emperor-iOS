import Foundation

/// One row of the Schedule to the Limitation Act, 1963, as the platform's radar carries it
/// (`src/features/limitation-radar/audit.js`). The texts are the product, so
/// `LimitationRadarGoldenTests` holds every string to the platform's own table.
struct LimitationProfile: Equatable, Sendable, Identifiable {
    var key: String
    var label: String
    var article: String
    var years: Int
    /// The Schedule's third column: the event time begins to run from.
    var runsFrom: String

    var id: String { key }

    /// The picker's wording: "<label> — <article>, <years> years".
    var pickerLabel: String { "\(label) — \(article), \(years) years" }

    static let defaultKey = "contract_compensation"

    static let all: [LimitationProfile] = [
        LimitationProfile(
            key: "contract_compensation", label: "Compensation for breach of contract",
            article: "Article 55", years: 3,
            runsFrom: "When the contract is broken; for successive breaches, when the breach sued on occurs; for a continuing breach, when it ceases."),
        LimitationProfile(
            key: "money_lent", label: "Money payable for money lent",
            article: "Article 19", years: 3, runsFrom: "When the loan is made."),
        LimitationProfile(
            key: "specific_performance", label: "Specific performance of a contract",
            article: "Article 54", years: 3,
            runsFrom: "The date fixed for performance or, if none was fixed, when the plaintiff had notice that performance was refused."),
        LimitationProfile(
            key: "declaration", label: "Any other declaration",
            article: "Article 58", years: 3, runsFrom: "When the right to sue first accrues."),
        LimitationProfile(
            key: "mortgage_money",
            label: "Money secured by a mortgage or charged on immovable property",
            article: "Article 62", years: 12, runsFrom: "When the money sued for becomes due."),
        LimitationProfile(
            key: "mortgage_foreclosure", label: "Foreclosure by a mortgagee",
            article: "Article 63(a)", years: 30,
            runsFrom: "When the money secured by the mortgage becomes due."),
        LimitationProfile(
            key: "residuary", label: "Any other suit (residuary)",
            article: "Article 113", years: 3, runsFrom: "When the right to sue accrues."),
    ]

    static func profile(for key: String) -> LimitationProfile {
        all.first { $0.key == key } ?? all[0]
    }
}

/// The request body of `POST /limitation-radar`. Empty optionals are omitted: the server reads
/// an empty string as absent, and an absent key is the plainer way to say it.
struct LimitationAuditRequest: Encodable, Equatable, Sendable {
    var profile: String
    var causeOfAction: String
    var intendedFiling: String
    var mediationStart: String?
    var mediationEnd: String?
    /// Filled in by the service from the signed-in account; the server ignores it today.
    var userId: String?

    enum CodingKeys: String, CodingKey {
        case profile
        case causeOfAction = "cause_of_action"
        case intendedFiling = "intended_filing"
        case mediationStart = "mediation_start"
        case mediationEnd = "mediation_end"
        case userId
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(profile, forKey: .profile)
        try c.encode(causeOfAction, forKey: .causeOfAction)
        try c.encode(intendedFiling, forKey: .intendedFiling)
        if let mediationStart, !mediationStart.isEmpty {
            try c.encode(mediationStart, forKey: .mediationStart)
        }
        if let mediationEnd, !mediationEnd.isEmpty {
            try c.encode(mediationEnd, forKey: .mediationEnd)
        }
        if let userId { try c.encode(userId, forKey: .userId) }
    }
}

/// How the audit came out, from the answer's `status_color`: an unknown colour reads as barred,
/// as the page does.
enum LimitationOutcome: Equatable, Sendable {
    case safe, mediation, barred

    init(statusColor: String?) {
        switch statusColor {
        case "emerald": self = .safe
        case "amber": self = .mediation
        default: self = .barred
        }
    }
}

/// The audit the server computed. Integers are read leniently (a whole number may arrive as a
/// double).
struct LimitationAudit: Decodable, Equatable, Sendable {
    struct Mediation: Decodable, Equatable, Sendable {
        var start: String
        var end: String
        var endAssumed: Bool
        var capped: Bool
        var beganAfterExpiry: Bool
        var excludedDays: Int

        enum CodingKeys: String, CodingKey {
            case start, end, capped
            case endAssumed = "end_assumed"
            case beganAfterExpiry = "began_after_expiry"
            case excludedDays = "excluded_days"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            start = try c.decode(String.self, forKey: .start)
            end = try c.decode(String.self, forKey: .end)
            endAssumed = try c.decodeIfPresent(Bool.self, forKey: .endAssumed) ?? false
            capped = try c.decodeIfPresent(Bool.self, forKey: .capped) ?? false
            beganAfterExpiry = try c.decodeIfPresent(Bool.self, forKey: .beganAfterExpiry) ?? false
            excludedDays = c.lenientInt(.excludedDays) ?? 0
        }

        init(
            start: String, end: String, endAssumed: Bool = false, capped: Bool = false,
            beganAfterExpiry: Bool = false, excludedDays: Int = 0
        ) {
            self.start = start
            self.end = end
            self.endAssumed = endAssumed
            self.capped = capped
            self.beganAfterExpiry = beganAfterExpiry
            self.excludedDays = excludedDays
        }
    }

    var status: String
    var statusColor: String
    var statuteApplied: String
    var daysOverdue: Int
    var fatalFlaw: String
    var curativeStrategies: [String]
    var profile: String
    var profileLabel: String
    var article: String
    var limitationYears: Int
    var periodRunsFrom: String
    var causeOfAction: String
    var intendedFiling: String
    var bareDeadline: String
    var mediation: Mediation?
    var adjustedDeadline: String
    var adjustedDaysOverdue: Int
    var reliesOnMediationExclusion: Bool
    var computedAt: String?

    var outcome: LimitationOutcome { LimitationOutcome(statusColor: statusColor) }

    enum CodingKeys: String, CodingKey {
        case status, profile, article, mediation
        case statusColor = "status_color"
        case statuteApplied = "statute_applied"
        case daysOverdue = "days_overdue"
        case fatalFlaw = "fatal_flaw"
        case curativeStrategies = "curative_strategies"
        case profileLabel = "profile_label"
        case limitationYears = "limitation_years"
        case periodRunsFrom = "period_runs_from"
        case causeOfAction = "cause_of_action"
        case intendedFiling = "intended_filing"
        case bareDeadline = "bare_deadline"
        case adjustedDeadline = "adjusted_deadline"
        case adjustedDaysOverdue = "adjusted_days_overdue"
        case reliesOnMediationExclusion = "relies_on_mediation_exclusion"
        case computedAt = "computed_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        status = try c.decode(String.self, forKey: .status)
        statusColor = try c.decodeIfPresent(String.self, forKey: .statusColor) ?? "red"
        statuteApplied = try c.decodeIfPresent(String.self, forKey: .statuteApplied) ?? ""
        daysOverdue = c.lenientInt(.daysOverdue) ?? 0
        fatalFlaw = try c.decodeIfPresent(String.self, forKey: .fatalFlaw) ?? ""
        curativeStrategies = try c.decodeIfPresent([String].self, forKey: .curativeStrategies) ?? []
        profile = try c.decodeIfPresent(String.self, forKey: .profile) ?? ""
        profileLabel = try c.decodeIfPresent(String.self, forKey: .profileLabel) ?? ""
        article = try c.decodeIfPresent(String.self, forKey: .article) ?? ""
        limitationYears = c.lenientInt(.limitationYears) ?? 0
        periodRunsFrom = try c.decodeIfPresent(String.self, forKey: .periodRunsFrom) ?? ""
        causeOfAction = try c.decodeIfPresent(String.self, forKey: .causeOfAction) ?? ""
        intendedFiling = try c.decodeIfPresent(String.self, forKey: .intendedFiling) ?? ""
        bareDeadline = try c.decode(String.self, forKey: .bareDeadline)
        mediation = try c.decodeIfPresent(Mediation.self, forKey: .mediation)
        adjustedDeadline =
            try c.decodeIfPresent(String.self, forKey: .adjustedDeadline) ?? bareDeadline
        adjustedDaysOverdue = c.lenientInt(.adjustedDaysOverdue) ?? 0
        reliesOnMediationExclusion =
            try c.decodeIfPresent(Bool.self, forKey: .reliesOnMediationExclusion) ?? false
        computedAt = try c.decodeIfPresent(String.self, forKey: .computedAt)
    }

    init(
        status: String, statusColor: String, statuteApplied: String = "", daysOverdue: Int,
        fatalFlaw: String = "", curativeStrategies: [String] = [], profile: String = "",
        profileLabel: String = "", article: String = "", limitationYears: Int = 3,
        periodRunsFrom: String = "", causeOfAction: String = "", intendedFiling: String = "",
        bareDeadline: String, mediation: Mediation? = nil, adjustedDeadline: String? = nil,
        adjustedDaysOverdue: Int = 0, reliesOnMediationExclusion: Bool = false,
        computedAt: String? = nil
    ) {
        self.status = status
        self.statusColor = statusColor
        self.statuteApplied = statuteApplied
        self.daysOverdue = daysOverdue
        self.fatalFlaw = fatalFlaw
        self.curativeStrategies = curativeStrategies
        self.profile = profile
        self.profileLabel = profileLabel
        self.article = article
        self.limitationYears = limitationYears
        self.periodRunsFrom = periodRunsFrom
        self.causeOfAction = causeOfAction
        self.intendedFiling = intendedFiling
        self.bareDeadline = bareDeadline
        self.mediation = mediation
        self.adjustedDeadline = adjustedDeadline ?? bareDeadline
        self.adjustedDaysOverdue = adjustedDaysOverdue
        self.reliesOnMediationExclusion = reliesOnMediationExclusion
        self.computedAt = computedAt
    }
}

extension KeyedDecodingContainer {
    /// An integer that may have been written as a double; `nil` when absent or not a number.
    fileprivate func lenientInt(_ key: Key) -> Int? {
        if let i = try? decodeIfPresent(Int.self, forKey: key) { return i }
        if let d = try? decodeIfPresent(Double.self, forKey: key) { return Int(d) }
        return nil
    }
}

/// The radar's refusal body: `{success:false, error:{code, message, detail}}`. `error` is an
/// object here, unlike almost every other route, which is why this does not go through
/// `APIClient.send`.
struct LimitationRadarError: Decodable, Equatable, Sendable {
    var code: String?
    var message: String?
    var detail: JSONValue?
}

struct LimitationRadarEnvelope: Decodable, Sendable {
    var success: Bool?
    var error: LimitationRadarError?
}
