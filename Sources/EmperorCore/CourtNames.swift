import Foundation

/// Names as courts print them, read the way a person writes them — a port of the platform's
/// `src/lib/courtNames.js` (`tidyCourtName`), which the server uses to name a matter made from a
/// tracked case and every screen uses to preview that name. Courts print in capitals
/// ("M/S PSTGEMS PRIVATE LIMITED vs. ALISHA ENTERPRISES"); this title-cases a shouting name,
/// keeps the abbreviations Indian litigation writes in capitals, and with `title: true` reads a
/// whole cause title (vs. / v/s / versus → "v.", capped at 200 UTF-16 units).
enum CourtNames {

    private static let keepCaps: Set<String> = [
        "UOI", "NCT", "GNCTD", "DDA", "MCD", "NDMC", "CBI", "ED", "NIA", "SBI", "RBI", "SEBI", "LIC", "NHAI",
        "ONGC", "BSES", "DMRC", "HDFC", "ICICI", "IDBI", "PNB", "BHEL", "NTPC", "GAIL", "IOCL", "BPCL", "HPCL", "AIIMS", "IIT", "UP",
        "MP", "HP", "J&K", "UT", "LLP", "HUF", "NGO", "CEO", "ITO", "CIT", "GST", "UK", "USA", "IT", "II", "III", "IV", "ANR.", "ORS.",
    ]
    private static let smallWords: Set<String> = [
        "AND", "OF", "THE", "FOR", "IN", "AS", "TO", "BY", "ON", "AT", "OR", "THROUGH", "WITH",
    ]
    private static let separator = MatterPattern("^(VS\\.?|V/S\\.?|VERSUS)$")
    private static let loneV = MatterPattern("^V\\.?$")
    private static let beforeInitial = MatterPattern("^([A-Z]\\.?|[SDWC]/O\\.?)$")
    private static let letterRun = MatterPattern("[A-Za-z][A-Za-z']*")
    private static let nonLetters = MatterPattern("[^A-Za-z]")
    private static let digit = MatterPattern("[0-9]")

    /// One run of letters in a capitalised word, in title case.
    private static func titleRun(_ run: String, next: Character?) -> String {
        if run.count == 1 || keepCaps.contains(run.uppercased()) { return run }
        if run.count == 2, next != ".", next != "-" { return run }
        return String(run.prefix(1)) + run.dropFirst().lowercased()
    }

    /// `tidyCourtName(raw, { title })`.
    static func tidy(_ raw: String?, title: Bool = false) -> String {
        let words = JSCompat.trim(JSCompat.collapse(raw ?? "")).components(separatedBy: " ")
        let ups = words.map { $0.uppercased() }
        let explicit = ups.contains { separator.test($0) }
        func isVersus(_ i: Int) -> Bool {
            guard title else { return false }
            if separator.test(ups[i]) { return true }
            return !explicit && loneV.test(ups[i]) && i > 0 && i < ups.count - 1 && !beforeInitial.test(ups[i - 1])
        }
        // Shouting is judged without the separators: courts write "vs." in lower case.
        let joined = words.indices.filter { !separator.test(ups[$0]) && !loneV.test(ups[$0]) }.map { words[$0] }.joined()
        let letters = nonLetters.replace(in: joined, with: "")
        let shouting = letters.count > 3 && letters == letters.uppercased()
        let name = words.indices.map { i -> String in
            let w = words[i], up = ups[i]
            if isVersus(i) { return "v." }
            if !shouting { return w }
            if up == "M/S" || up == "M/S." { return "M/s" }
            if up == "ANR." || up == "ANR" { return "Anr." }
            if up == "ORS." || up == "ORS" { return "Ors." }
            if i > 0, smallWords.contains(up) { return w.lowercased() }
            if keepCaps.contains(up) || digit.test(w) { return w }
            let units = Array(w.utf16)
            return letterRun.replace(in: w) { run, at in
                let nextIndex = at + run.utf16.count
                let next = nextIndex < units.count ? Character(Unicode.Scalar(units[nextIndex]) ?? " ") : nil
                return titleRun(run, next: next)
            }
        }.joined(separator: " ")
        if title, name.utf16.count > 200 { return JSCompat.prefixUTF16(name, 197) + "…" }
        return name
    }
}
