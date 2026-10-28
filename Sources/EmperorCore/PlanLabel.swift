import Foundation

/// What the plan pill and the plan row say.
///
/// The account carries more than one label. `/auth/session` sends the customer-facing name
/// (Junior Associate, Senior Associate, Partner); `/preferred-model` sends the internal tier
/// (`Lite`, `Premium`, `Ultra`), and the app stores whichever answered last. The web's top bar
/// never shows an internal tier (`Topbar.jsx`), so neither does this: every surface that shows
/// `planLabel` goes through here.
enum PlanLabel {
    /// The capability tiers, which are never a plan name.
    static let internalTiers: Set<String> = ["None", "Lite", "Premium", "Ultra"]

    /// The label as a customer should read it, or `nil` when it is empty or an internal tier.
    static func customerFacing(_ raw: String?) -> String? {
        guard let text = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty,
              !internalTiers.contains(text)
        else { return nil }
        return text
    }

    /// The pill's text: the account's own name for its plan, else the tier's name from the
    /// allowances, else "Plan".
    static func pill(session: String?, entitlements: EntitlementsResponse.Limits?) -> String {
        pill(session: session, tierLabel: entitlements?.label)
    }

    static func pill(session: String?, tierLabel: String?) -> String {
        customerFacing(session) ?? customerFacing(tierLabel) ?? "Plan"
    }

    /// The account card's pill: "Junior Associate plan", or "Plan" when nothing customer-facing
    /// is known.
    static func accountPill(session: String?) -> String {
        guard let name = customerFacing(session) else { return "Plan" }
        return "\(name) plan"
    }
}
