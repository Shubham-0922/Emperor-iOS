#if DEBUG
import Foundation

/// The UI tests' canned answers for the Limitation Radar (`POST /limitation-radar`). Owned by
/// package 10-R. Stateless: the answer depends only on the request.
///
/// The bodies are copied from `Tests/EmperorCoreTests/Resources/parity/radar/limitation-radar.json`
/// (made by `scripts/generate-limitation-radar-fixtures.mjs`): the amber one is audit
/// `mediation-reliant-amber`, the red one `barred-residuary-17-days`, the refusals are routes
/// `missing-cause` and `filing-before-cause`.
enum RadarStubs {
    static func reply(_ request: URLRequest, _ path: String) -> StubReply? {
        guard path == "/limitation-radar" else { return nil }
        guard request.httpMethod == "POST",
              let body = UITestSupport.Fixtures.jsonBody(of: request)
        else { return StubReply.json(missingCause, status: 404) }

        let cause = (body["cause_of_action"] as? String) ?? ""
        let filing = (body["intended_filing"] as? String) ?? ""
        if cause.isEmpty || filing.isEmpty { return .json(missingCause, status: 400) }

        switch body["profile"] as? String {
        case "declaration": return .json(filingBeforeCause, status: 400)
        case "residuary": return .json(barred)
        default: return .json(mediation)
        }
    }

    private static let missingCause = #"{"success":false,"error":{"code":"MISSING_ARGUMENT","message":"cause_of_action is required."}}"#

    private static let filingBeforeCause = #"{"success":false,"error":{"code":"INVALID_TIMELINE","message":"The filing date is earlier than the cause of action. Check both dates.","detail":{"field":"intended_filing"}}}"#

    private static let mediation = #"{"success":true,"status":"WITHIN TIME ONLY WITH THE SECTION 12A EXCLUSION","status_color":"amber","statute_applied":"Article 55, Limitation Act, 1963 — 3 years (Compensation for breach of contract)","days_overdue":36,"fatal_flaw":"Counting 3 years under Article 55 from 15 January 2023, the last day to file is 15 January 2026. The filing on 20 February 2026 is 36 days after that, and is in time only if the 60 days spent in pre-institution mediation are excluded under Section 12A(5) of the Commercial Courts Act, 2015, which moves the last day to 16 March 2026.","curative_strategies":["File on or before 16 March 2026, and plead the Section 12A(5) exclusion expressly in the plaint.","The exclusion applies only to a commercial dispute of specified value in which pre-institution mediation under Section 12A was actually undertaken. Confirm both before relying on it.","Keep the mediation application and the Mediation Authority's report: they are the proof of the dates excluded.","Without the exclusion the suit is 36 days late, and delay in filing a suit cannot be condoned — Section 5 applies to appeals and applications, not suits."],"profile":"contract_compensation","profile_label":"Compensation for breach of contract","article":"Article 55","limitation_years":3,"period_runs_from":"When the contract is broken; for successive breaches, when the breach sued on occurs; for a continuing breach, when it ceases.","cause_of_action":"2023-01-15","intended_filing":"2026-02-20","bare_deadline":"2026-01-15","mediation":{"start":"2025-12-01","end":"2026-01-30","end_assumed":false,"capped":false,"began_after_expiry":false,"excluded_days":60},"adjusted_deadline":"2026-03-16","adjusted_days_overdue":-24,"relies_on_mediation_exclusion":true}"#

    private static let barred = #"{"success":true,"status":"LEGALLY BARRED / EXPIRED","status_color":"red","statute_applied":"Article 113, Limitation Act, 1963 — 3 years (Any other suit (residuary))","days_overdue":17,"fatal_flaw":"Counting 3 years under Article 113 from 15 January 2023, the last day to file is 15 January 2026. The filing on 1 February 2026 is 17 days late. Under Section 3 a suit filed after the prescribed period must be dismissed, even if limitation is not raised as a defence.","curative_strategies":["Delay in filing a suit cannot be condoned. Section 5 applies only to appeals and applications, so the remedy lies in showing that the period has not in fact expired.","Section 18: a written acknowledgment of liability, signed by the defendant before 15 January 2026, starts a fresh period from the date it was signed.","Section 19: a payment on account of the debt or interest, made before the period expired, starts a fresh period from the date of payment.","Section 14: if a civil proceeding on the same matter was prosecuted in good faith in a court without jurisdiction, the time it was pending is excluded.","Section 17: where the right or the facts were concealed by fraud, or the suit is for relief from a mistake, time runs from when it was discovered.","Check whether the suit, as actually framed, falls under a different article with a longer period or a later starting point."],"profile":"residuary","profile_label":"Any other suit (residuary)","article":"Article 113","limitation_years":3,"period_runs_from":"When the right to sue accrues.","cause_of_action":"2023-01-15","intended_filing":"2026-02-01","bare_deadline":"2026-01-15","mediation":null,"adjusted_deadline":"2026-01-15","adjusted_days_overdue":17,"relies_on_mediation_exclusion":false}"#
}
#endif
