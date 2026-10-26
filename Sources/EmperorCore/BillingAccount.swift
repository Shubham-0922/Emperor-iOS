import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The plan's own record from `GET /billing/me`: how it was come by and when it ends.
/// Read only; the orders the route also carries are not decoded.
struct BillingPlanStatus: Decodable, Equatable, Sendable {
    var planSource: String?
    var expiresAt: Date?
    var expired: Bool?
    var displayLabel: String?
    var marketingPlanLabel: String?
    var feeTier: String?
    var legacy: Bool?

    init(planSource: String? = nil, expiresAt: Date? = nil, expired: Bool? = nil,
         displayLabel: String? = nil, marketingPlanLabel: String? = nil,
         feeTier: String? = nil, legacy: Bool? = nil) {
        self.planSource = planSource
        self.expiresAt = expiresAt
        self.expired = expired
        self.displayLabel = displayLabel
        self.marketingPlanLabel = marketingPlanLabel
        self.feeTier = feeTier
        self.legacy = legacy
    }

    private enum CodingKeys: String, CodingKey {
        case planSource, expiresAt, expired, displayLabel, marketingPlanLabel, feeTier, legacy
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        planSource = try? c.decodeIfPresent(String.self, forKey: .planSource)
        if let text = try? c.decodeIfPresent(String.self, forKey: .expiresAt) {
            expiresAt = WireDate.parse(text)
        } else if let millis = try? c.decodeIfPresent(Double.self, forKey: .expiresAt) {
            expiresAt = WireDate.fromEpochMillis(millis)
        }
        expired = try? c.decodeIfPresent(Bool.self, forKey: .expired)
        displayLabel = try? c.decodeIfPresent(String.self, forKey: .displayLabel)
        marketingPlanLabel = try? c.decodeIfPresent(String.self, forKey: .marketingPlanLabel)
        feeTier = try? c.decodeIfPresent(String.self, forKey: .feeTier)
        legacy = try? c.decodeIfPresent(Bool.self, forKey: .legacy)
    }
}

protocol BillingAccountProviding: Sendable {
    func planStatus() async throws -> BillingPlanStatus?
}

struct BillingAccountService: BillingAccountProviding {
    let client: APIClient

    private struct Envelope: Decodable {
        var success: Bool?
        var plan: BillingPlanStatus?
    }

    func planStatus() async throws -> BillingPlanStatus? {
        let request = try await client.makeRequest("GET", "/billing/me")
        return try await client.send(request, as: Envelope.self).plan
    }
}

/// The plan's standing, worded as the billing page's `statusOf` words it.
struct PlanStanding: Equatable, Sendable {
    enum Tone: Equatable, Sendable { case neutral, success, warning, danger }
    var text: String
    var tone: Tone

    /// "No plan" is keyed off the plan's source, not its tier: every account carries a tier
    /// from the day it is created.
    static func of(_ plan: BillingPlanStatus?, now: Date) -> PlanStanding {
        guard let plan, let source = plan.planSource, !source.isEmpty else {
            return PlanStanding(text: "No plan", tone: .neutral)
        }
        if plan.expired == true { return PlanStanding(text: "Expired", tone: .danger) }
        guard let expires = plan.expiresAt else { return PlanStanding(text: "Active", tone: .success) }
        let days = Int((expires.timeIntervalSince(now) / 86_400).rounded(.up))
        if days <= 0 { return PlanStanding(text: "Expires today", tone: .warning) }
        if days < 14 {
            return PlanStanding(text: "Expires in \(days) day\(days == 1 ? "" : "s")", tone: .warning)
        }
        return PlanStanding(text: "Active", tone: .success)
    }

    static let sourceWords: [String: String] = [
        "purchase": "purchased", "coupon": "free trial",
        "admin": "granted by admin", "grandfathered": "included",
    ]

    /// "purchased · Active until 12 November 2026"; `nil` for an account with no plan.
    static func sourceLine(_ plan: BillingPlanStatus, now: Date) -> String? {
        guard let source = plan.planSource, !source.isEmpty else { return nil }
        let words = sourceWords[source] ?? source
        let tail: String
        if source == "grandfathered" {
            tail = "No expiry"
        } else if let date = plan.expiresAt {
            tail = (plan.expired == true ? "Expired on " : "Active until ") + day(date)
        } else {
            tail = "No expiry"
        }
        return "\(words) · \(tail)"
    }

    nonisolated(unsafe) private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMMM yyyy"
        f.locale = Locale(identifier: "en_IN")
        f.timeZone = WireDate.india
        return f
    }()

    static func day(_ date: Date) -> String { dayFormatter.string(from: date) }
}
