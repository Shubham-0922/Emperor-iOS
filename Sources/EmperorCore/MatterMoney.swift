import Foundation

/// Rupees for a matter's fees, payments and expenses — a port of the platform's
/// `src/components/projects/money/inr.js` and `inr()` of `src/lib/projectsApi.js`.
///
/// Everything is counted in whole paise: the API sends rupees as floats (`amount`) beside the
/// exact integer (`amount_paise`), and a figure is turned into paise once, at the edge. Indian
/// digit grouping is done by hand rather than with a `NumberFormatter`, whose output depends on
/// the ICU data of the platform it runs on.
enum INR {

    /// The amount field's ceiling. The server's is lower (`serverMaxRupees`): check that one
    /// before sending, or a valid-looking entry comes back "too large".
    static let maxRupees: Double = 1e12
    static let serverMaxRupees: Double = MatterRules.maxRupees

    private static let ones = ["", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine", "Ten",
                               "Eleven", "Twelve", "Thirteen", "Fourteen", "Fifteen", "Sixteen", "Seventeen", "Eighteen", "Nineteen"]
    private static let tens = ["", "", "Twenty", "Thirty", "Forty", "Fifty", "Sixty", "Seventy", "Eighty", "Ninety"]

    private static func under100(_ n: Int) -> String {
        n < 20 ? ones[n] : tens[n / 10] + (n % 10 != 0 ? " \(ones[n % 10])" : "")
    }

    private static func under1000(_ n: Int) -> String {
        [n >= 100 ? "\(ones[n / 100]) Hundred" : "", n % 100 != 0 ? under100(n % 100) : ""]
            .filter { !$0.isEmpty }.joined(separator: " ")
    }

    private static func indianWords(_ n: Int) -> String {
        if n == 0 { return "Zero" }
        let crore = n / 10_000_000
        let lakh = (n % 10_000_000) / 100_000
        let thousand = (n % 100_000) / 1000
        let rest = n % 1000
        return [crore != 0 ? "\(indianWords(crore)) Crore" : "",
                lakh != 0 ? "\(under100(lakh)) Lakh" : "",
                thousand != 0 ? "\(under100(thousand)) Thousand" : "",
                rest != 0 ? under1000(rest) : ""].filter { !$0.isEmpty }.joined(separator: " ")
    }

    private static func exactInt(_ d: Double) -> Int? {
        guard d.isFinite, abs(d) < 9.0e18 else { return nil }
        return Int(d)
    }

    /// `toPaise(number)`: rounded to the nearest paisa (the API's floats are two-decimal values).
    static func toPaise(number: Double) -> Int? {
        guard number.isFinite else { return nil }
        return exactInt(JSCompat.round(number * 100))
    }

    private static let groupingNoise = MatterPattern("[,\(JSCompat.spaceChars)]")
    private static let amountShape = MatterPattern("^(-?)([0-9]*)(?:\\.([0-9]*))?$")

    /// `toPaise(string)`: digits with grouping commas, half-up on the third decimal, done on the
    /// digits so a typed amount never takes the float detour.
    static func toPaise(text: String?) -> Int? {
        let s = groupingNoise.replace(in: text ?? "", with: "")
        guard let m = amountShape.groups(in: s) else { return nil }
        let whole = m[2] ?? "", fracRaw = m[3] ?? ""
        if whole.isEmpty && fracRaw.isEmpty { return nil }
        let frac = Array(fracRaw.padding(toLength: max(3, fracRaw.count), withPad: "0", startingAt: 0))
        let wholeValue = Double(whole.isEmpty ? "0" : whole) ?? 0
        let paiseValue = Double(String(frac[0...1])) ?? 0
        let up: Double = (frac[2].wholeNumberValue ?? 0) >= 5 ? 1 : 0
        let paise = wholeValue * 100 + paiseValue + up
        guard let p = exactInt(paise) else { return nil }
        return m[1] == "-" ? -p : p
    }

    /// `amountInWordsINR`: "Rupees Twelve Lakh … and Fifty Paise Only"; "Fifty Paise Only" under a
    /// rupee; "" for nothing, a negative amount, or more than `maxRupees`.
    static func words(paise: Int?) -> String {
        guard let paise, paise >= 0, Double(paise) <= maxRupees * 100 else { return "" }
        let rupees = paise / 100
        let p = paise % 100
        if rupees == 0 && p != 0 { return "\(under100(p)) Paise Only" }
        return "Rupees \(indianWords(rupees))\(p != 0 ? " and \(under100(p)) Paise" : "") Only"
    }

    /// What the amount field accepted, in both units.
    struct Parsed: Equatable, Sendable {
        let paise: Int
        let rupees: Double
    }

    /// Why the amount field refused, in the web's words.
    struct ParseError: Error, Equatable, Sendable {
        let message: String
    }

    private static let currencyPrefix = MatterPattern("^(₹|rs\\.?|inr)[\(JSCompat.spaceChars)]*", caseInsensitive: true)
    private static let closingDash = MatterPattern("/-$")
    private static let digitsShape = MatterPattern("^[0-9]*(\\.[0-9]*)?$")

    /// `parseRupees`: digits with any grouping commas, an optional ₹ / Rs / INR in front, the
    /// receipt-style "/-" after, at most two decimals, more than ₹0 and no more than `maxRupees`.
    static func parse(_ text: String?) -> Result<Parsed, ParseError> {
        var s = JSCompat.trim(text ?? "")
        s = currencyPrefix.replace(in: s, with: "")
        s = closingDash.replace(in: s, with: "")
        s = groupingNoise.replace(in: s, with: "")
        if s.isEmpty { return .failure(ParseError(message: "Enter the amount.")) }
        if !digitsShape.test(s) || s == "." {
            return .failure(ParseError(message: "Use digits only, e.g. 25000 or 1,25,000.50."))
        }
        let parts = s.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        let whole = String(parts[0])
        let frac = parts.count > 1 ? String(parts[1]) : ""
        if frac.count > 2 { return .failure(ParseError(message: "Paise take two decimals at most.")) }
        let paise = (Double(whole.isEmpty ? "0" : whole) ?? 0) * 100
            + (Double(frac.padding(toLength: 2, withPad: "0", startingAt: 0)) ?? 0)
        if !(paise > 0) { return .failure(ParseError(message: "The amount has to be more than ₹0.")) }
        if paise > maxRupees * 100 { return .failure(ParseError(message: "That amount is too large.")) }
        return .success(Parsed(paise: Int(paise), rupees: paise / 100))
    }

    /// `rupeesFigure`: "₹25,000/-" for whole rupees, "₹25,000.50" with paise; "" for nothing.
    static func figure(paise: Int?) -> String {
        guard let paise, paise >= 0 else { return "" }
        let rupees = JSCompat.indianGrouping(String(paise / 100))
        let p = paise % 100
        return p != 0 ? "₹\(rupees).\(p < 10 ? "0" : "")\(p)" : "₹\(rupees)/-"
    }

    /// `inr()`: ₹ with Indian grouping; whole rupees without decimals, paise always as two digits.
    static func display(rupees n: Double) -> String {
        let hasPaise = fmod(JSCompat.round(n * 100), 100) != 0
        return "₹" + JSCompat.indianNumber(n, minFraction: hasPaise ? 2 : 0, maxFraction: 2)
    }

    private static let dayPrefix = MatterPattern("^([0-9]{4})-([0-9]{2})-[0-9]{2}")

    /// `financialYear`: the April-to-March year a day falls in, "2026-27"; "" without a day.
    static func financialYear(_ day: String?) -> String {
        guard let m = dayPrefix.groups(in: day ?? ""), let y = Int(m[1]!), let month = Int(m[2]!) else { return "" }
        let start = month >= 4 ? y : y - 1
        return "\(start)-\(JSCompat.pad((start + 1) % 100, 2))"
    }

    /// `receiptNumber`: the payment's financial year and the last six letters/digits of the
    /// entry id, upper-cased — a number that never changes once printed.
    static func receiptNumber(id: String?, entryDate: String?, createdAt: String?) -> String {
        let day = (entryDate?.isEmpty == false) ? entryDate : createdAt
        let fy = financialYear(day)
        let alnum = (id ?? "").unicodeScalars.filter {
            (48...57).contains($0.value) || (65...90).contains($0.value) || (97...122).contains($0.value)
        }
        let tail = String(String.UnicodeScalarView(alnum.suffix(6))).uppercased()
        return [fy, tail.isEmpty ? "000000" : tail].filter { !$0.isEmpty }.joined(separator: "/")
    }
}

/// A matter's ledger — fees billed, payments received, expenses — as the Fees section reads it:
/// a port of the platform's `src/components/projects/money/ledger.js`.
enum Ledger {

    /// One `project_ledger` row, as much of it as the rules read.
    struct Entry: Equatable, Identifiable, Sendable {
        var id: String
        var kind: String
        var title: String?
        /// The exact integer column; nil when the server sent none (or a non-integer).
        var amountPaise: Int?
        /// The rupee float.
        var amount: Double?
        var entryDate: String?
        var createdAt: String?
        var mode: String?
        var reference: String?
        var category: String?
        var receiptFile: String?
        var notes: String?

        init(id: String, kind: String, title: String? = nil, amountPaise: Int? = nil, amount: Double? = nil,
             entryDate: String? = nil, createdAt: String? = nil, mode: String? = nil, reference: String? = nil,
             category: String? = nil, receiptFile: String? = nil, notes: String? = nil) {
            self.id = id
            self.kind = kind
            self.title = title
            self.amountPaise = amountPaise
            self.amount = amount
            self.entryDate = entryDate
            self.createdAt = createdAt
            self.mode = mode
            self.reference = reference
            self.category = category
            self.receiptFile = receiptFile
            self.notes = notes
        }
    }

    /// `rupees()`: `inr()` with paise always written as two digits.
    static func rupees(_ amount: Double) -> String {
        let s = INR.display(rupees: amount)
        let units = Array(s.utf16)
        if units.count >= 2, units[units.count - 2] == 0x2E, (0x30...0x39).contains(units[units.count - 1]) {
            return s + "0"
        }
        return s
    }

    /// What the reference box is called for each way of paying.
    struct ReferenceField: Equatable, Sendable {
        let label: String
        let placeholder: String
    }

    static func referenceField(mode: String?) -> ReferenceField? {
        switch mode {
        case "upi": return ReferenceField(label: "UPI ref. / UTR", placeholder: "12-digit UPI reference")
        case "bank": return ReferenceField(label: "UTR / transaction ref.", placeholder: "NEFT / RTGS / IMPS UTR")
        case "cheque": return ReferenceField(label: "Cheque no. and bank", placeholder: "e.g. 004512, HDFC Bank")
        case "cash": return ReferenceField(label: "Voucher no.", placeholder: "Optional")
        case "card": return ReferenceField(label: "Transaction ID", placeholder: "From the card slip")
        case "other": return ReferenceField(label: "Reference", placeholder: "How it was paid")
        default: return nil
        }
    }

    static let expenseReference = ReferenceField(label: "Challan / receipt no.", placeholder: "e.g. e-court fee GRN, challan no.")

    /// `modeLabel`: "" for an unknown mode.
    static func modeLabel(_ mode: String?) -> String {
        mode.flatMap(MatterVocabulary.PaymentMode.init(rawValue:))?.label ?? ""
    }

    /// `categoryLabel`: "Other" for an unknown category.
    static func categoryLabel(_ category: String?) -> String {
        category.flatMap(MatterVocabulary.ExpenseCategory.init(rawValue:))?.label ?? "Other"
    }

    /// `paiseOf`: the integer column when there is one, the rupee float otherwise.
    static func paise(of entry: Entry) -> Int {
        if let p = entry.amountPaise { return p }
        return entry.amount.flatMap { INR.toPaise(number: $0) } ?? 0
    }

    /// `sortEntries`: newest first — by the day the money moved, then by when it was entered.
    static func sorted(_ entries: [Entry]) -> [Entry] {
        JSCompat.stableSorted(entries) { a, b in
            let da = MatterDates.dayKeyOf(a.entryDate), db = MatterDates.dayKeyOf(b.entryDate)
            if da != db { return JSCompat.localeCompare(db, da) }
            return JSCompat.localeCompare(b.createdAt ?? "", a.createdAt ?? "")
        }
    }

    /// `ledgerTotals`: the fallback when `GET /project` sends no totals, summed in paise.
    static func totals(_ entries: [Entry]) -> MatterRules.LedgerTotals {
        MatterRules.ledgerTotals(entries.filter { ["fee", "payment", "expense"].contains($0.kind) }
            .map { (kind: $0.kind, paise: paise(of: $0)) })
    }

    /// Expenses of one category.
    struct CategoryTotal: Equatable, Sendable {
        let key: String
        let label: String
        var paise: Int
        var count: Int
    }

    /// `expenseCategories`: unknown categories counted as other; largest first, then by label.
    static func expenseCategories(_ entries: [Entry]) -> [CategoryTotal] {
        var order: [String] = []
        var rows: [String: CategoryTotal] = [:]
        for e in entries where e.kind == "expense" {
            let key = e.category.flatMap(MatterVocabulary.ExpenseCategory.init(rawValue:)) != nil ? e.category! : "other"
            var row = rows[key] ?? CategoryTotal(key: key, label: categoryLabel(key), paise: 0, count: 0)
            if rows[key] == nil { order.append(key) }
            row.paise += paise(of: e)
            row.count += 1
            rows[key] = row
        }
        return JSCompat.stableSorted(order.map { rows[$0]! }) { a, b in
            a.paise != b.paise ? (b.paise > a.paise ? 1 : -1) : JSCompat.localeCompare(a.label, b.label)
        }
    }

    /// One file of a matter, for the receipt picker.
    struct ProjectFileRef: Equatable, Sendable {
        /// The file's name.
        let name: String
        /// Relative to the user's storage root — what `receipt_file` stores.
        let path: String
        /// The sub-folder inside the matter, "" for its root.
        let folder: String
    }

    /// `projectFileList`: every file of a `GET /project-files` answer, flattened; Receipts first,
    /// then the other folders and names in order. `items` is the answer's folders then its files.
    static func projectFileList(root: String?, items: [FileNode]) -> [ProjectFileRef] {
        var rootPath = (root ?? "").replacingOccurrences(of: "\\", with: "/")
        while rootPath.hasSuffix("/") { rootPath.removeLast() }
        var out: [ProjectFileRef] = []
        func walk(_ nodes: [FileNode]) {
            for node in nodes {
                switch node {
                case .folder(let f): walk(f.files ?? [])
                case .file(let f):
                    let path = (f.path.isEmpty ? f.name : f.path).replacingOccurrences(of: "\\", with: "/")
                    if path.isEmpty { continue }
                    let dir = path.contains("/") ? String(path[..<path.lastIndex(of: "/")!]) : ""
                    let folder = !rootPath.isEmpty && (dir == rootPath || dir.hasPrefix(rootPath + "/"))
                        ? String(dir.dropFirst(rootPath.count + 1)) : dir
                    out.append(ProjectFileRef(name: f.name.isEmpty ? baseName(path) : f.name, path: path, folder: folder))
                }
            }
        }
        walk(items)
        func isReceipts(_ f: ProjectFileRef) -> Int {
            let lower = f.folder.lowercased()
            return lower == "receipts" || lower.hasPrefix("receipts/") ? 1 : 0
        }
        return JSCompat.stableSorted(out) { a, b in
            let r = isReceipts(b) - isReceipts(a)
            if r != 0 { return r }
            let f = JSCompat.localeCompare(a.folder, b.folder)
            return f != 0 ? f : JSCompat.localeCompare(a.name, b.name)
        }
    }

    private static func baseName(_ path: String) -> String {
        path.components(separatedBy: "/").last ?? ""
    }

    /// `receiptFileName`: the name to show for a stored `receipt_file` path.
    static func receiptFileName(_ path: String?) -> String {
        baseName((path ?? "").replacingOccurrences(of: "\\", with: "/"))
    }
}
