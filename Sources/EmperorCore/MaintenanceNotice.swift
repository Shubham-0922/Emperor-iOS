import Foundation

/// The notice on Home while the platform is down for maintenance, as the web's
/// `src/lib/backendHealth.js` decides it from `GET /maintenance`.
///
/// Asked at launch and whenever the app comes to the foreground — not on a timer. While it is on,
/// every other route answers with the maintenance refusal anyway (`APIClient`), so the notice is
/// a heads-up, not the only signal.
enum MaintenanceNotice {

    /// Shown only when the server says the outage applies to this caller.
    static func shouldShow(_ state: MaintenanceState?) -> Bool {
        state?.active == true
    }

    /// What the banner says: the operator's own words when there are any.
    static func message(for state: MaintenanceState) -> String {
        let written = state.message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return written.isEmpty
            ? "Emperor is down for maintenance. Some things may not work until it is back."
            : written
    }
}
