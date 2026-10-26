import Foundation

/// The Devil's Advocate report as one printable page, for the app's PDF and Word downloads.
///
/// The web's "Download report" is the browser's print of the page with every weak spot opened;
/// this is that print written as plain HTML — headings, the header facts, tables — which
/// `AnswerPDF` and `DocxDocument` both read. Every value is escaped.
enum DevilsAdvocateExport {

    static func html(_ report: DevilsAdvocateReport, madeOn: String) -> String {
        var out = ""
        let title = report.matter.title.isEmpty ? "Your matter" : report.matter.title
        out += "<p><b>Devil's Advocate report</b></p>"
        out += "<h1>\(esc(title))</h1>"
        let meta = report.meta(madeOn: madeOn)
        if !meta.isEmpty {
            out += table(head: nil, rows: meta.map { [$0.label, $0.value] })
        }
        out += "<p><b>\(esc(report.exposureBand)) exposure</b> (\(report.exposureScore) out of 100). \(esc(report.countsLine)).</p>"
        out += "<p><b>\(esc(DevilsAdvocateReport.disclaimerLead))</b> \(esc(DevilsAdvocateReport.disclaimer))</p>"

        if !report.oneMinute.isEmpty {
            out += "<h2>In one minute</h2><ol>"
            out += report.oneMinute.map { "<li>\(esc($0))</li>" }.joined()
            out += "</ol>"
        }

        out += "<h2>Your weak spots, ranked</h2>"
        if report.weakSpots.isEmpty {
            out += "<p>\(esc(DevilsAdvocateReport.noSpots))</p>"
        }
        for spot in report.weakSpots {
            let category = DevilsAdvocateReport.categoryLabel(spot.category)
            out += "<h3>\(spot.id). \(esc(spot.title))</h3>"
            out += "<p><i>\(esc(spot.severity.label)) · \(esc(category)) · likelihood \(spot.likelihood) of 5, impact \(spot.impact) of 5</i></p>"
            if !spot.why.isEmpty { out += "<p><b>Why it hurts.</b> \(esc(spot.why))</p>" }
            if !spot.where.isEmpty { out += "<p><b>Where in your papers.</b> \(esc(spot.where.joined(separator: "; ")))</p>" }
            if !spot.say.isEmpty { out += "<p><b>What they will say.</b> \"\(esc(spot.say))\"</p>" }
            if !spot.fix.isEmpty { out += "<p><b>How to close the gap.</b> \(esc(spot.fix))</p>" }
        }

        out += "<h2>Questions you should expect</h2>"
        if report.questions.isEmpty {
            out += "<p>\(esc(DevilsAdvocateReport.noQuestions))</p>"
        } else {
            out += table(
                head: ["They will ask", "Why they ask", "Your best answer or paper to have ready", "Readiness"],
                rows: report.questions.map { q in
                    let answer = q.spot.map { "\(q.answer) (#\($0))" } ?? q.answer
                    return ["\"\(q.q)\"", q.why.isEmpty ? "—" : q.why, answer, q.readiness.label]
                })
        }

        out += "<h2>Papers you are missing</h2>"
        if report.docGaps.isEmpty {
            out += "<p>\(esc(DevilsAdvocateReport.noGaps))</p>"
        } else {
            out += table(
                head: ["Document", "Who has it", "How to get it", "By when", "Closes"],
                rows: report.docGaps.map { d in
                    [d.doc, dash(d.who), dash(d.how), dash(d.when), d.spot.map { "#\($0)" } ?? "·"]
                })
        }

        out += "<h2>Authorities that cut against you</h2>"
        if report.authorities.isEmpty {
            out += "<p>\(esc(DevilsAdvocateReport.noAuthorities))</p>"
        } else {
            out += table(
                head: ["Authority", "What it generally holds", "How to distinguish it", "Hurts"],
                rows: report.authorities.map { a in
                    var name = "See e.g. \(a.name)"
                    let place = [[a.court, a.year].filter { !$0.isEmpty }.joined(separator: ", "), a.pinCite]
                        .filter { !$0.isEmpty }.joined(separator: " · ")
                    if !place.isEmpty { name += " (\(place))" }
                    if a.verify { name += ". \(DevilsAdvocateReport.verifyBadge)" }
                    return [name, dash(a.holds), dash(a.distinguish), a.against.map { "#\($0)" } ?? "·"]
                })
        }
        out += "<p><b>\(esc(DevilsAdvocateReport.verifyLead))</b> \(esc(DevilsAdvocateReport.verifyNote))</p>"

        out += "<h2>Your preparation checklist</h2>"
        if report.checklist.isEmpty {
            out += "<p>\(esc(DevilsAdvocateReport.noChecklist))</p>"
        } else {
            out += "<ul>" + report.checklist.map { "<li>\($0.done ? "☑" : "☐") \(esc($0.text))</li>" }.joined() + "</ul>"
        }
        return out
    }

    private static func dash(_ s: String) -> String { s.isEmpty ? "—" : s }

    private static func table(head: [String]?, rows: [[String]]) -> String {
        var out = "<table>"
        if let head {
            out += "<thead><tr>" + head.map { "<th>\(esc($0))</th>" }.joined() + "</tr></thead>"
        }
        out += "<tbody>"
        out += rows.map { "<tr>" + $0.map { "<td>\(esc($0))</td>" }.joined() + "</tr>" }.joined()
        return out + "</tbody></table>"
    }

    /// Text made safe inside HTML.
    static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
