import Foundation

/// The dates and lines the History panel and its banner write (`useAnalysisHistory.js`,
/// `AnalysisHistory.jsx`), and the report's "made on" day (`DevilsAdvocate.jsx`).
///
/// Written out by hand rather than through a locale's formatter: the web's English short months
/// say "Sept", and a formatter's say whatever the device's locale data says that year.
enum AnalysisHistoryFormat {

    private static let shortMonths = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sept", "Oct", "Nov", "Dec"]
    private static let longMonths = [
        "January", "February", "March", "April", "May", "June", "July", "August", "September",
        "October", "November", "December",
    ]

    private static func parts(_ date: Date, _ zone: TimeZone) -> DateComponents {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
    }

    /// "27 Oct 2026".
    static func shortDay(_ date: Date, timeZone: TimeZone = .current) -> String {
        let p = parts(date, timeZone)
        return "\(p.day!) \(shortMonths[p.month! - 1]) \(p.year!)"
    }

    /// "27 Oct 2026, 3:04 pm", or "" for a date that is not one.
    static func fullDate(_ iso: String?, timeZone: TimeZone = .current) -> String {
        guard let date = WireDate.parse(iso) else { return "" }
        return fullDate(date, timeZone: timeZone)
    }

    static func fullDate(_ date: Date, timeZone: TimeZone = .current) -> String {
        let p = parts(date, timeZone)
        let hour = p.hour!
        let twelve = hour % 12 == 0 ? 12 : hour % 12
        let minute = p.minute! < 10 ? "0\(p.minute!)" : "\(p.minute!)"
        return "\(shortDay(date, timeZone: timeZone)), \(twelve):\(minute) \(hour < 12 ? "am" : "pm")"
    }

    /// "just now", "5 min ago", "3 h ago", "2 d ago", then the day itself from a fortnight on.
    static func ago(_ iso: String?, now: Date = Date(), timeZone: TimeZone = .current) -> String {
        guard let date = WireDate.parse(iso) else { return "" }
        return ago(date, now: now, timeZone: timeZone)
    }

    static func ago(_ date: Date, now: Date = Date(), timeZone: TimeZone = .current) -> String {
        let s = max(0, AnalysisJS.round(now.timeIntervalSince(date)))
        if s < 60 { return "just now" }
        let m = AnalysisJS.round(s / 60)
        if m < 60 { return "\(Int(m)) min ago" }
        let h = AnalysisJS.round(m / 60)
        if h < 24 { return "\(Int(h)) h ago" }
        let d = AnalysisJS.round(h / 24)
        if d < 14 { return "\(Int(d)) d ago" }
        return shortDay(date, timeZone: timeZone)
    }

    /// "a.pdf, b.pdf +3".
    static func fileLine(_ names: [String]) -> String {
        names.count <= 2 ? names.joined(separator: ", ") : "\(names.prefix(2).joined(separator: ", ")) +\(names.count - 2)"
    }

    /// "27 October 2026": the day a report was made.
    static func madeOn(_ date: Date, timeZone: TimeZone = .current) -> String {
        let p = parts(date, timeZone)
        return "\(p.day!) \(longMonths[p.month! - 1]) \(p.year!)"
    }

    /// "Read 3 documents: a.pdf, b.pdf and 1 more", the line above every result.
    static func provenance(_ names: [String]) -> String {
        let shown = names.prefix(2).joined(separator: ", ")
        let more = names.count > 2 ? " and \(names.count - 2) more" : ""
        return "Read \(names.count) document\(names.count == 1 ? "" : "s"): \(shown)\(more)"
    }

    /// Said after the provenance line when the run had a note.
    static let withReference = "· with your reference note"
}
