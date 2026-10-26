import Foundation

/// The two documents a matter prints: a payment's fee receipt and the List of Dates — assembled
/// from the workspace's payload with the web's own builders (`MatterReceipt`, `MatterRecord`), so
/// the PDF on a phone reads word for word as the web's printout.
enum MatterPrintouts {

    /// A payment's receipt, without the on-screen Print bar (a PDF has no button to press). The
    /// advocate is the signed-in account; the client and their address come from the matter.
    static func receiptHTML(entry: LedgerEntry, detail: ProjectDetail, user: User?) -> String {
        let p = detail.project
        return MatterReceipt.html(
            advocate: MatterReceipt.advocate(
                name: user?.name, title: user?.title, organization: user?.organization, phone: user?.phone,
                email: user?.email),
            client: MatterReceipt.client(
                projectClient: p.client,
                people: detail.people.map { MatterReceipt.Person(role: $0.role, name: $0.name, address: $0.address) }),
            matter: MatterReceipt.matter(
                name: p.name, caseNumber: p.caseNumber, caseType: p.caseType, caseYear: p.caseYear,
                forumName: p.forumName),
            entry: entry.ledgerEntry, includePrintBar: false)
    }

    /// "Receipt 2026-27-A1B2C3.pdf".
    static func receiptFileName(_ entry: LedgerEntry) -> String {
        let number = INR.receiptNumber(id: entry.id, entryDate: entry.entryDateRaw, createdAt: entry.createdAtRaw)
        return "Receipt \(number.replacingOccurrences(of: "/", with: "-")).pdf"
    }

    /// The List of Dates and Events, in the synopsis format.
    static func listOfDatesHTML(detail: ProjectDetail) -> String {
        let p = detail.project
        let linked = detail.linkedCase.map {
            MatterRecord.LinkedCaseInput(courtName: $0.courtName, caseType: $0.caseType, caseNumber: $0.caseNumber,
                                         caseYear: $0.caseYear)
        }
        let entries = MatterRecord.chronology(
            updates: detail.updates.map(\.recordUpdate), court: detail.courtHistory.map(\.recordItem))
        return MatterRecord.listOfDatesHtml(
            project: MatterRecord.ListOfDatesInput(
                name: p.name, forumName: p.forumName, caseType: p.caseType, caseNumber: p.caseNumber,
                caseYear: p.caseYear, client: p.client, oppositeParty: p.oppositeParty, ourSide: p.ourSide),
            linkedCase: linked, entries: entries)
    }

    /// "List of Dates — Bhalla v. State.pdf", with characters a file name cannot hold taken out.
    static func listOfDatesFileName(_ project: Project) -> String {
        let name = project.displayName.components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>")).joined(separator: " ")
        return "List of Dates — \(String(name.prefix(80))).pdf"
    }
}
