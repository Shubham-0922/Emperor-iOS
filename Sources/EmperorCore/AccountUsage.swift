import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(Darwin)
import Observation
#endif

/// This month's allowances and how much of each is used — the platform's usage meters.
///
/// Read from `GET /billing/entitlements`, which the web's usage page draws from. **Read only,
/// and nothing here sells anything.** The route also returns prices, overage rates and an
/// `upgradable` flag; none of it is decoded, because this app takes no money and links to
/// nothing that does. What a person gets from this screen is the answer to "why was that
/// refused?" before it happens: how many questions are left, and when they renew.
struct AccountUsage: Equatable, Sendable {

    /// One allowance. Rows, titles, order and tones follow the web's usage meter
    /// (`UsageMeter.jsx` `rowsFor`, `useEntitlements.js` `usageTone`).
    struct Meter: Equatable, Sendable, Identifiable {
        enum Kind: String, Equatable, Sendable, CaseIterable {
            case questions, deepThinking, scannedPages, documents, matters, storage
        }

        /// The web's tone: accent while comfortable, warn from 80%, danger once spent.
        enum Tone: String, Equatable, Sendable { case accent, warn, danger }

        var kind: Kind
        var used: Double
        /// `nil` when there is no limit. The platform writes "unlimited" as `-1` or omits it
        /// (`planLimits.unlimited`), and both become `nil` here.
        var limit: Double?

        var id: Kind { kind }

        /// 0…1 of the allowance used, or nil when there is no limit to measure against.
        var fraction: Double? {
            guard let limit, limit > 0 else { return nil }
            return min(1, max(0, used / limit))
        }

        var isUnlimited: Bool { limit == nil || (limit ?? 0) < 0 }

        var isExhausted: Bool {
            guard let limit, limit > 0 else { return false }
            return used >= limit
        }

        /// Most of it gone: worth drawing differently before it runs out.
        var isRunningLow: Bool { (fraction ?? 0) >= 0.8 && !isExhausted }

        var tone: Tone {
            guard let limit, limit > 0 else { return .accent }
            let ratio = used / limit
            if ratio >= 1 { return .danger }
            if ratio >= 0.8 { return .warn }
            return .accent
        }

        /// The meter's state in words — "Used up", "Running low" — or `nil` when there is
        /// nothing to say. A colour is not a statement: it says nothing to VoiceOver.
        var statusLabel: String? {
            if isExhausted { return "Used up" }
            if isRunningLow { return "Running low" }
            return nil
        }

        var title: String {
            switch kind {
            case .questions: return "Chat queries"
            case .deepThinking: return "Deep thinking"
            case .scannedPages: return "Scanned pages"
            case .documents: return "Documents"
            case .matters: return "Tracked matters"
            case .storage: return "Storage"
            }
        }

        var usedText: String { format(used) }
        var limitText: String { format(limit ?? 0) }

        /// "120 of 1,000", "2.4 GB of 50 GB", "37 · no limit".
        var summary: String {
            guard !isUnlimited else { return "\(usedText) · no limit" }
            return "\(usedText) of \(limitText)"
        }

        /// Deep-thinking questions are a sub-allowance *inside* the questions allowance.
        var note: String? {
            kind == .deepThinking ? "After these, Thinking queries are answered in standard mode"
                : nil
        }

        private func format(_ value: Double) -> String {
            if kind == .storage { return AccountUsage.bytes(value) }
            return DisplayText.grouped(Int(value.rounded()))
        }
    }

    /// A line of the product copy: a core feature, or a roadmap row.
    struct ProductFeature: Equatable, Sendable, Identifiable {
        enum Status: Equatable, Sendable { case included, comingSoon, inDevelopment }
        var key: String
        var label: String
        var status: Status
        var id: String { key }
    }

    /// The account's raw catalogue label. Not what the top bar shows — see `PlanLabel`.
    var planLabel: String?
    /// Whether limits are enforced on this account. Staff and demo accounts are not metered, and
    /// are shown their usage with no limits rather than limits they are not held to.
    var isMetered: Bool
    /// The plan's dated period has ended.
    var hasExpired: Bool
    /// When this month's allowances start again — midnight in India on the 1st.
    var renewsOn: Date?
    var meters: [Meter]
    /// The tier's own name — "Junior Associate", or "Earlier plan" for a retired plan.
    var planTierLabel: String? = nil
    var supportLabel: String? = nil
    /// The plan's storage in bytes (`storageBytes`); `nil` when not sent, negative when unlimited.
    var storageBytes: Double? = nil
    var filingReady: Bool? = nil
    var cloudSync: Bool? = nil
    var productFeatures: [ProductFeature] = []

    /// Storage the way the web's `fmtBytes` says it: binary units, India's digit grouping,
    /// "2.4 GB", "850 MB". A plan's "50 GB" is 50 GiB, so a decimal reading showed a full
    /// allowance as short of it.
    static func bytes(_ value: Double) -> String {
        let n = value.isFinite ? value : 0
        let gb = 1_073_741_824.0, mb = 1_048_576.0
        if n >= gb {
            let v = n / gb
            return "\(indian(v, maxFraction: v >= 100 ? 0 : 1)) GB"
        }
        return "\(indian(max(0, (n / mb).rounded(.toNearestOrAwayFromZero)), maxFraction: 0)) MB"
    }

    private static func indian(_ v: Double, maxFraction: Int) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_IN")
        f.numberStyle = .decimal
        f.usesGroupingSeparator = true
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = maxFraction
        f.roundingMode = .halfUp
        return f.string(from: NSNumber(value: v)) ?? String(v)
    }
}

// MARK: - Wire

/// The parts of `/billing/entitlements` this client reads. Everything optional: the response
/// is wide, changes often, and a field it stops sending must not cost the whole screen.
struct EntitlementsResponse: Decodable, Sendable {
    var success: Bool?
    var signedIn: Bool?
    var feeTier: String?
    var planLabel: String?
    var expired: Bool?
    var metered: Bool?
    var limits: Limits?
    var usage: Usage?
    var features: Features?
    var storageBytes: Double?
    var support: String?
    /// Decoded and never shown: nothing is charged for going over, and a quoted price is
    /// sales copy.
    var overageRates: JSONValue?
    var coreFeatures: [CoreFeature]?
    var roadmap: [RoadmapItem]?

    struct Limits: Decodable, Sendable {
        var label: String?
        var matters: Double?
        var storageGb: Double?
        var documents: Double?
        var scannedPages: Double?
        var chatQueries: Double?
        var deepThinkingQueries: Double?
        var support: String?
    }

    struct Usage: Decodable, Sendable {
        var resetsAt: String?
        var chatQueries: Double?
        var deepThinkingQueries: Double?
        var scannedPages: Double?
        var documents: Double?
        var matters: Double?
        var storageUsedBytes: Double?
        var storageAllowanceBytes: Double?
    }

    struct Features: Decodable, Sendable {
        var filingReady: Bool?
        var cloudSync: Bool?
    }

    struct CoreFeature: Decodable, Sendable {
        var key: String
        var label: String
        var comingSoon: Bool?
    }

    struct RoadmapItem: Decodable, Sendable {
        var key: String
        var label: String
        var status: String?
        var detail: String?
    }

    /// Converts to the screen's model, row for row as the web's `rowsFor` draws it. Count
    /// limits are dropped for an unmetered account (`effectiveLimits`); storage keeps its
    /// allowance. With no `usage` in the answer there is nothing to draw, as on the web.
    var usageModel: AccountUsage {
        let metered = metered ?? false
        func limit(_ raw: Double?) -> Double? {
            guard metered, let raw, raw >= 0 else { return nil }
            return raw
        }
        var meters: [AccountUsage.Meter] = []
        if let usage {
            let storageLimit: Double? = {
                if let allowance = usage.storageAllowanceBytes {
                    return allowance >= 0 ? allowance : nil
                }
                if let gb = limits?.storageGb, gb >= 0 { return gb * 1_073_741_824 }
                return nil
            }()
            meters.append(.init(kind: .questions, used: usage.chatQueries ?? 0,
                                limit: limit(limits?.chatQueries)))
            // Only plans that cap them show deep thinking, documents and matters.
            if let cap = limit(limits?.deepThinkingQueries) {
                meters.append(.init(kind: .deepThinking, used: usage.deepThinkingQueries ?? 0, limit: cap))
            }
            meters.append(.init(kind: .scannedPages, used: usage.scannedPages ?? 0,
                                limit: limit(limits?.scannedPages)))
            if let cap = limit(limits?.documents) {
                meters.append(.init(kind: .documents, used: usage.documents ?? 0, limit: cap))
            }
            if let cap = limit(limits?.matters) {
                meters.append(.init(kind: .matters, used: usage.matters ?? 0, limit: cap))
            }
            meters.append(.init(kind: .storage, used: usage.storageUsedBytes ?? 0, limit: storageLimit))
        }

        var features: [AccountUsage.ProductFeature] = []
        for item in coreFeatures ?? [] {
            features.append(.init(key: item.key, label: item.label,
                                  status: item.comingSoon == true ? .comingSoon : .included))
        }
        for item in roadmap ?? [] {
            features.append(.init(key: item.key, label: item.label,
                                  status: item.status == "available" ? .included : .inDevelopment))
        }
        return AccountUsage(
            planLabel: planLabel,
            isMetered: metered,
            hasExpired: expired ?? false,
            renewsOn: WireDate.parse(usage?.resetsAt),
            meters: meters,
            planTierLabel: limits?.label,
            supportLabel: support,
            storageBytes: storageBytes,
            filingReady: self.features?.filingReady,
            cloudSync: self.features?.cloudSync,
            productFeatures: features)
    }
}

protocol UsageProviding: Sendable {
    func usage() async throws -> AccountUsage
}

struct UsageService: UsageProviding {
    let client: APIClient

    func usage() async throws -> AccountUsage {
        let request = try await client.makeRequest("GET", "/billing/entitlements")
        return try await client.send(request, as: EntitlementsResponse.self).usageModel
    }
}

// MARK: - View model

#if canImport(Darwin)
@Observable
#endif
@MainActor
final class AccountUsageViewModel {
    private(set) var usage: AccountUsage?
    private(set) var planStatus: BillingPlanStatus?
    private(set) var state: LoadState = .idle

    private let service: any UsageProviding
    private let billing: (any BillingAccountProviding)?
    private let now: @Sendable () -> Date

    init(service: any UsageProviding, billing: (any BillingAccountProviding)? = nil,
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.service = service
        self.billing = billing
        self.now = now
    }

    /// Reads the allowances and, alongside, the plan's standing. A failed standing read is not
    /// an error: the allowances still show.
    func load() async {
        state = .loading
        async let status: BillingPlanStatus? = { [billing] in
            guard let billing else { return nil }
            return try? await billing.planStatus()
        }()
        do {
            usage = try await service.usage()
            state = .loaded
        } catch {
            state = .failed(LoadFailure(error))
        }
        planStatus = await status
    }

    /// The line under the plan's name.
    var renewalLine: String? {
        guard let usage else { return nil }
        if usage.hasExpired { return "This account's plan has ended." }
        guard usage.isMetered else { return "No usage limits apply to this account." }
        return usage.renewsOn.map { "Monthly allowances renew on \(DisplayText.renewalDay($0))." }
    }

    /// The meters worth a row — exactly the web's list.
    var visibleMeters: [AccountUsage.Meter] { usage?.meters ?? [] }

    /// The plan's name as a customer knows it: the billing page's label, else what the account
    /// carries, never an internal tier.
    func planName(sessionLabel: String?) -> String {
        PlanLabel.customerFacing(planStatus?.displayLabel)
            ?? PlanLabel.customerFacing(planStatus?.marketingPlanLabel)
            ?? PlanLabel.pill(session: sessionLabel, tierLabel: usage?.planTierLabel)
    }

    var standing: PlanStanding? {
        planStatus.map { PlanStanding.of($0, now: now()) }
    }

    var sourceLine: String? {
        planStatus.flatMap { PlanStanding.sourceLine($0, now: now()) }
    }

    /// Support, storage and the two features the plan may or may not include.
    var includedRows: [(title: String, value: String)] {
        guard let usage else { return [] }
        var rows: [(String, String)] = []
        if let support = usage.supportLabel, !support.isEmpty { rows.append(("Support", support)) }
        if let bytes = usage.storageBytes {
            rows.append(("Storage", bytes < 0 ? "Unlimited" : AccountUsage.bytes(bytes)))
        }
        if let on = usage.filingReady { rows.append(("Filing Ready", on ? "Included" : "Not on your plan")) }
        if let on = usage.cloudSync { rows.append(("Cloud Sync", on ? "Included" : "Not on your plan")) }
        return rows
    }

    var productFeatures: [AccountUsage.ProductFeature] { usage?.productFeatures ?? [] }
}
