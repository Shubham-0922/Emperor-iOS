import Foundation

/// The printable fee receipt for one payment — a port of the platform's
/// `src/components/projects/money/receipt.js` (`printReceipt`, which drives a browser window, is
/// not ported). The HTML is byte-for-byte the web's, so a receipt printed on the phone is the
/// receipt a client already holds from the web; every value is escaped.
enum MatterReceipt {

    /// The advocate block at the head of the receipt.
    struct Advocate: Equatable, Sendable {
        var name: String
        var designation: String
        var chambers: String
        var phone: String
        var email: String

        init(name: String = "", designation: String = "", chambers: String = "", phone: String = "", email: String = "") {
            self.name = name
            self.designation = designation
            self.chambers = chambers
            self.phone = phone
            self.email = email
        }
    }

    /// Who the receipt is made out to.
    struct Client: Equatable, Sendable {
        var name: String
        var address: String

        init(name: String = "", address: String = "") {
            self.name = name
            self.address = address
        }
    }

    /// The matter the money was paid in.
    struct Matter: Equatable, Sendable {
        var title: String
        var caseNo: String
        var forum: String

        init(title: String = "", caseNo: String = "", forum: String = "") {
            self.title = title
            self.caseNo = caseNo
            self.forum = forum
        }
    }

    /// A person on the matter, as `receiptClient` reads the People section.
    struct Person: Equatable, Sendable {
        var role: String?
        var name: String?
        var address: String?

        init(role: String? = nil, name: String? = nil, address: String? = nil) {
            self.role = role
            self.name = name
            self.address = address
        }
    }

    private static func clean(_ v: String?) -> String { JSCompat.clean(v) }

    /// `caseNumberOf`: "CS(OS) 55/2018" — the type prefixed only when the number lacks it.
    static func caseNumber(caseNumber: String?, caseType: String?, caseYear: String?) -> String {
        let num = clean(caseNumber)
        guard !num.isEmpty else { return "" }
        let type = clean(caseType)
        let typed = !type.isEmpty && !num.lowercased().hasPrefix(type.lowercased()) ? "\(type) \(num)" : num
        let year = clean(caseYear)
        return !year.isEmpty && !typed.hasSuffix("/\(year)") ? "\(typed)/\(year)" : typed
    }

    /// `receiptClient`: the matter's client, with the address from the People section when that
    /// record is the same person (another name is never swapped in); the first client on record
    /// when the matter names none.
    static func client(projectClient: String?, people: [Person]) -> Client {
        let named = clean(projectClient)
        let clients = people.filter { $0.role == "client" && !clean($0.name).isEmpty }
        let same = named.isEmpty ? clients.first : clients.first { clean($0.name).lowercased() == named.lowercased() }
        return Client(name: named.isEmpty ? clean(same?.name) : named, address: clean(same?.address))
    }

    /// `advocateFromProfile`: a valid Indian mobile is written "+91 98765 43210"; anything else
    /// (a landline) as typed.
    static func advocate(name: String?, title: String?, organization: String?, phone: String?, email: String?) -> Advocate {
        let p = clean(phone)
        let shown = !p.isEmpty && IndianMobile.isValid(p) ? "+\(IndianMobile.countryCode) \(IndianMobile.local(p))" : p
        return Advocate(name: clean(name), designation: clean(title), chambers: clean(organization), phone: shown,
                        email: clean(email))
    }

    /// `matterFromProject`.
    static func matter(name: String?, caseNumber: String?, caseType: String?, caseYear: String?, forumName: String?) -> Matter {
        Matter(title: clean(name),
               caseNo: self.caseNumber(caseNumber: caseNumber, caseType: caseType, caseYear: caseYear),
               forum: clean(forumName))
    }

    private static let stampAbovePaise = 5000 * 100

    private static func esc(_ v: String) -> String {
        var out = ""
        for ch in v {
            switch ch {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&#39;"
            default: out.append(ch)
            }
        }
        return out
    }

    /// `paidBy`: how the money came, in the receipt's own sentence.
    static func paidBy(mode: String?, reference: String?) -> String {
        let ref = clean(reference)
        switch mode {
        case "cash": return "in cash"
        case "upi": return "by UPI\(ref.isEmpty ? "" : " (ref. \(ref))")"
        case "bank": return "by bank transfer\(ref.isEmpty ? "" : " (UTR \(ref))")"
        case "cheque": return "by cheque\(ref.isEmpty ? "" : " no. \(ref)")"
        case "card": return "by card\(ref.isEmpty ? "" : " (txn \(ref))")"
        default: return ref.isEmpty ? "" : "(ref. \(ref))"
        }
    }

    private static let blank = "<span class=\"blank\"></span>"
    private static let printBar = "<div class=\"bar\"><button type=\"button\" id=\"receipt-print\">Print</button><span>To keep a copy, choose “Save as PDF” in the print dialog.</span></div>\n"
    private static let theWord = MatterPattern("^the\(JSCompat.spaceClass)", caseInsensitive: true)

    /// `buildReceiptHtml`. With `includePrintBar: false` only the on-screen Print bar is left out
    /// — for a PDF, which has no button to press.
    static func html(advocate: Advocate = Advocate(), client: Client = Client(), matter: Matter = Matter(),
                     entry: Ledger.Entry, includePrintBar: Bool = true) -> String {
        let paise = Ledger.paise(of: entry)
        let number = INR.receiptNumber(id: entry.id, entryDate: entry.entryDate, createdAt: entry.createdAt)
        let rupees = Double(paise) / 100
        let figure = INR.figure(paise: INR.toPaise(number: rupees))
        let words = INR.words(paise: INR.toPaise(number: rupees))
        let date = MatterDates.fmtDay(entry.entryDate)
        let titled = clean(entry.title)
        let towards = titled.isEmpty ? "professional fees" : titled
        let by = paidBy(mode: entry.mode, reference: entry.reference)
        let forum = matter.forum.isEmpty ? "" : "before \(theWord.test(matter.forum) ? "" : "the ")\(esc(matter.forum))"
        let titleText = esc(matter.title)
        let matterText = ["<b>\(titleText.isEmpty ? blank : titleText)</b>", matter.caseNo.isEmpty ? "" : esc(matter.caseNo), forum]
            .filter { !$0.isEmpty }.joined(separator: ", ")
        let contacts = [advocate.phone, advocate.email].filter { !$0.isEmpty }.map(esc).joined(separator: " &middot; ")
        let signer = advocate.name.isEmpty ? advocate.email : advocate.name
        let docTitle = "Receipt \(number)\(client.name.isEmpty ? "" : " — \(client.name)")"
        let who = esc(advocate.name)
        let clientName = esc(client.name)
        let dateText = esc(date)

        return """
        <!doctype html>
        <html lang="en-IN">
        <head>
        <meta charset="utf-8">
        <title>\(esc(docTitle))</title>
        <style>
          @page { size: A4; margin: 16mm 18mm; }
          * { box-sizing: border-box; }
          html { -webkit-print-color-adjust: exact; print-color-adjust: exact; }
          /* Times New Roman, the face Indian courts ask for, and lining figures: Georgia's old-style
             digits dip below the line, which is wrong on a column of amounts and case numbers. */
          body { margin: 0; background: #ECEEF5; color: #0F1424; font: 16px/1.6 'Times New Roman', Times, 'Liberation Serif', serif;
            font-variant-numeric: lining-nums; }
          .bar { display: flex; align-items: center; justify-content: center; gap: 14px; padding: 12px; background: #F7F8FC;
            border-bottom: 1px solid #E8EAF2; font: 13px/1.4 system-ui, -apple-system, 'Segoe UI', sans-serif; color: #454B63; }
          .bar button { height: 34px; padding: 0 18px; border: 0; border-radius: 4px; cursor: pointer; color: #fff;
            font: 600 13px/1 system-ui, -apple-system, 'Segoe UI', sans-serif; background: linear-gradient(135deg, #464E85 0%, #547592 100%); }
          .sheet { width: 190mm; margin: 24px auto; padding: 16mm 15mm 14mm; background: #fff;
            box-shadow: 0 1px 2px rgba(15, 20, 36, .08), 0 10px 28px -14px rgba(15, 20, 36, .22); }
          .head { text-align: center; padding-bottom: 12px; border-bottom: 2px solid #0F1424; }
          .who { font-size: 21px; font-weight: 700; letter-spacing: .06em; text-transform: uppercase; }
          .sub { font-size: 13.5px; color: #454B63; }
          .title { margin: 22px 0 0; text-align: center; font-size: 15px; font-weight: 700; letter-spacing: .32em; }
          .meta { display: flex; justify-content: space-between; gap: 16px; margin: 18px 0 20px; font-size: 14px; }
          .meta .no { font-family: ui-monospace, 'SFMono-Regular', Menlo, Consolas, monospace; font-size: 13.5px; }
          .text { margin: 0; text-align: justify; }
          .blank { display: inline-block; min-width: 46mm; border-bottom: 1px solid #0F1424; }
          .foot { display: flex; justify-content: space-between; align-items: flex-end; gap: 18px; margin-top: 30px; }
          .figure { padding: 8px 16px; border: 1.5px solid #0F1424; font-size: 18px; font-weight: 700; white-space: nowrap; }
          .sign { display: flex; align-items: flex-end; gap: 16px; }
          .stamp { display: grid; place-items: center; width: 24mm; height: 28mm; border: 1px dashed #8C93B0;
            font: 10.5px/1.3 system-ui, sans-serif; color: #8C93B0; text-align: center; }
          .sig { min-width: 62mm; text-align: center; font-size: 13.5px; line-height: 1.45; }
          .sig .rule { height: 16mm; border-bottom: 1px solid #0F1424; margin-bottom: 6px; }
          @media print {
            body { background: #fff; }
            .bar { display: none; }
            .sheet { width: auto; margin: 0; padding: 0; box-shadow: none; }
          }
        </style>
        </head>
        <body>
        \(includePrintBar ? printBar : "")<main class="sheet">
          <header class="head">
            <div class="who">\(who.isEmpty ? "&nbsp;" : who)</div>
            \(advocate.designation.isEmpty ? "" : "<div class=\"sub\">\(esc(advocate.designation))</div>")
            \(advocate.chambers.isEmpty ? "" : "<div class=\"sub\">\(esc(advocate.chambers))</div>")
            \(contacts.isEmpty ? "" : "<div class=\"sub\">\(contacts)</div>")
          </header>
          <div class="title">RECEIPT</div>
          <div class="meta"><span>Receipt No. <b class="no">\(esc(number))</b></span><span>Date: <b>\(dateText.isEmpty ? blank : dateText)</b></span></div>
          <p class="text">Received with thanks from <b>\(clientName.isEmpty ? blank : clientName)</b>\(client.address.isEmpty ? "" : ", \(esc(client.address)),")
            the sum of <b>\(esc(figure))</b> (<b>\(esc(words))</b>)\(by.isEmpty ? "" : " \(esc(by))") towards \(esc(towards)) in the
            matter of \(matterText).</p>
          <div class="foot">
            <div class="figure">\(esc(figure))</div>
            <div class="sign">
              \(paise > stampAbovePaise ? "<div class=\"stamp\">Revenue<br>stamp</div>" : "")
              <div class="sig"><div class="rule"></div>\(signer.isEmpty ? "" : "<b>\(esc(signer))</b><br>")\(esc(advocate.designation.isEmpty ? "Advocate" : advocate.designation))</div>
            </div>
          </div>
        </main>
        </body>
        </html>
        """
    }
}
