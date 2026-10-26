import Foundation

/// The Library's words and colours, ported from the web's own helpers so a card reads the same on
/// both: `src/components/library/coverTheme.js` (a collection's label, blurb and cloth; a tidied
/// title; what a cover prints; the facts under a card), `caselaw/courts.js` (a court's names, a
/// case name, a case number), `acts/actText.js` (an Act's title, kicker, cloth and counts),
/// `books/bookFormat.js` (volumes and series) and `caselaw/readerModel.js` (a citation line).
///
/// Held to the platform by `LibraryDisplayGoldenTests`, whose fixture
/// `scripts/generate-library-fixtures.mjs` writes by running those modules under Node. The regular
/// expressions are the web's, written for ICU: `[0-9]` where the web says `\d`, because ICU's `\d`
/// takes every script's digits and JavaScript's only ASCII ones.
enum LibraryDisplay {

    // MARK: - Collections

    /// A collection's vocabulary: its label, what a cover's top line calls one of its documents,
    /// the name an untitled one is given, a blurb, its cloth colours (the same in both themes —
    /// a red book is red in a dark room) and its ink on a light and a dark page.
    struct Theme: Equatable, Sendable {
        let key: String
        let label: String
        let cap: String
        let untitled: String
        let blurb: String
        let cloth: [String]
        let ink: String
        let inkDark: String
        let systemImage: String
    }

    /// The cream lettering on every cover. 4.5:1 or better on every cloth (`LibraryPaletteTests`).
    static let coverInk = "#F6F0E1"
    /// The gilt of a cover's rules — decorative only.
    static let coverGilt = "#D4B46A"

    private static let themes: [String: Theme] = [
        "bare-acts": Theme(
            key: "bare-acts", label: "Bare acts", cap: "Bare act", untitled: "Untitled Act",
            blurb: "Every central and state Act, with its rules, regulations and notifications.",
            cloth: ["#6E1F2A", "#7A2632", "#5F1A24"], ink: "#8C2A37", inkDark: "#EBA3AC",
            systemImage: "scroll"),
        "case-law": Theme(
            key: "case-law", label: "Case law", cap: "Judgment", untitled: "Untitled judgment",
            blurb: "Judgments of the Supreme Court and the High Courts, searchable word for word.",
            cloth: ["#1F2E4D", "#253860", "#1A2742"], ink: "#2B4373", inkDark: "#A9BDEB",
            systemImage: "building.columns"),
        "books-and-law-reports": Theme(
            key: "books-and-law-reports", label: "Books and law reports", cap: "Book",
            untitled: "Untitled volume",
            blurb: "Commentaries, digests and bound law reports, volume by volume.",
            cloth: ["#1F4A3A", "#265643", "#1A3F31", "#2D4630", "#1B4047"], ink: "#23624A",
            inkDark: "#97D3B8", systemImage: "book"),
        "regulator-orders": Theme(
            key: "regulator-orders", label: "Regulator orders", cap: "Order", untitled: "Regulator order",
            blurb: "Orders, circulars and directions from SEBI, RBI and other regulators.",
            cloth: ["#1D4B55", "#225763", "#183F48"], ink: "#1F5F6C", inkDark: "#93CFDA",
            systemImage: "seal"),
        "tribunals": Theme(
            key: "tribunals", label: "Tribunals", cap: "Tribunal", untitled: "Tribunal decision",
            blurb: "Decisions of TDSAT and the Armed Forces Tribunal, with NHRC publications.",
            cloth: ["#4A2747", "#552D52", "#3F213C"], ink: "#6A3766", inkDark: "#D9AED5",
            systemImage: "scale.3d"),
        "law-commission-reports": Theme(
            key: "law-commission-reports", label: "Law Commission reports", cap: "Report",
            untitled: "Law Commission report",
            blurb: "Reports of the Law Commission of India, from the first to the latest.",
            cloth: ["#3B3570", "#443D7E", "#332E62"], ink: "#4A4390", inkDark: "#B8B1EE",
            systemImage: "text.book.closed"),
        "professional-institutes": Theme(
            key: "professional-institutes", label: "Professional institutes", cap: "Institute",
            untitled: "Institute publication",
            blurb: "Standards and guidance from ICAI, ICSI and ICMAI.",
            cloth: ["#33363D", "#3C3F47", "#2B2D33"], ink: "#4A4E58", inkDark: "#C4C8D2",
            systemImage: "graduationcap"),
        "parliament-prs": Theme(
            key: "parliament-prs", label: "Parliament", cap: "Parliament", untitled: "Parliamentary paper",
            blurb: "Bills as introduced and passed, with PRS summaries and committee reports.",
            cloth: ["#8A3F22", "#964628", "#7A371D"], ink: "#9A4724", inkDark: "#F0B497",
            systemImage: "building.2"),
        "legal-aid-nalsa": Theme(
            key: "legal-aid-nalsa", label: "Legal aid", cap: "Legal aid", untitled: "Legal aid report",
            blurb: "Reports and schemes of the National Legal Services Authority.",
            cloth: ["#7A5A17", "#86641B", "#6C4F13"], ink: "#7A5A17", inkDark: "#E8C77E",
            systemImage: "hand.raised"),
    ]

    private static let fallbackTheme = Theme(
        key: "", label: "Library", cap: "Document", untitled: "Untitled document", blurb: "",
        cloth: ["#3A3F5C", "#424867", "#33384F"], ink: "#464E85", inkDark: "#B7BEE6",
        systemImage: "books.vertical")

    /// A collection's theme; an unknown key gets the plain one (`categoryTheme`).
    static func theme(_ key: String?) -> Theme {
        guard let key, let theme = themes[key] else {
            let f = fallbackTheme
            return Theme(key: key ?? "", label: f.label, cap: f.cap, untitled: f.untitled, blurb: f.blurb,
                         cloth: f.cloth, ink: f.ink, inkDark: f.inkDark, systemImage: f.systemImage)
        }
        return theme
    }

    /// Every cloth a cover can be bound in: the nine collections', the fallback's, and the State
    /// cloths of the Acts index.
    static var allCloths: [String] {
        (LibraryCategoryKey.order.compactMap { themes[$0]?.cloth } + [fallbackTheme.cloth]).flatMap { $0 }
            + stateCloths + [unspecifiedCloth]
    }

    /// FNV-1a over UTF-16 code units (`hashOf`): the same document always gets the same cloth.
    static func hashOf(_ value: String) -> UInt32 {
        var h: UInt32 = 0x811c9dc5
        for unit in value.utf16 {
            h ^= UInt32(unit)
            h = h &* 0x01000193
        }
        return h
    }

    /// The cloth of a document's cover: volumes of one series share one, others vary by id.
    static func cloth(for doc: LibraryDoc) -> String {
        if doc.category == LibraryCategoryKey.bareActs.rawValue { return actCloth(doc) }
        let cloths = theme(doc.category).cloth
        let seed = doc.series.flatMap { $0.isEmpty ? nil : $0.lowercased() } ?? String(doc.id)
        return cloths[Int(hashOf(seed) % UInt32(cloths.count))]
    }

    // MARK: - Titles

    private static let uuidish = Pattern("^[0-9a-f]{6,}(-[0-9a-f]{3,}){2,}$", caseInsensitive: true)
    private static let junkTitle = Pattern(
        "^(view|download|pdf|accessible|click here|link|file|document)?[\\s_-]*(\\(?\\s*(pdf)?\\s*[0-9.]*\\s*[km]b\\s*\\)?)?$",
        caseInsensitive: true)
    private static let smallTitleWords = Pattern("\\b(Of|And|The|In|For|To|On|By|Or|An|A)\\b")

    /// The title as the row has it, debris removed — empty when nothing usable is left.
    static func cleanTitle(_ raw: String?) -> String {
        var t = raw ?? ""
        t = Pattern("[#*_`]+").replaceAll(t, " ")
        t = Pattern("^\\s*\\(\\s*[0-9]+\\s*\\)\\s*").replaceFirst(t, "")
        t = Pattern("[\\s_-]*\\(\\s*pdf[^)]*\\)\\s*$", caseInsensitive: true).replaceFirst(t, "")
        t = Pattern("^[^\\p{L}\\p{N}(]+").replaceFirst(t, "")
        t = Pattern("^\\(([^)]*)$").replaceFirst(t) { g, _ in g[1] ?? "" }
        t = JSCompat.trim(JSCompat.collapse(t))
        if t.isEmpty || junkTitle.test(t) || uuidish.test(t) { return "" }
        // An all-caps statute title reads as shouting at cover sizes; title-case it.
        if t.utf16.count > 12, t == t.uppercased(), Pattern("[A-Z]").test(t) {
            t = Pattern("\\b([a-z])").replaceAll(t.lowercased()) { g, _ in (g[1] ?? "").uppercased() }
            t = smallTitleWords.replaceAll(t) { g, offset in offset == 0 ? (g[0] ?? "") : (g[1] ?? "").lowercased() }
        }
        return capitalizeFirst(t)
    }

    /// True when the row has no usable title and `tidyTitle` had to name it.
    static func isUntitled(_ doc: LibraryDoc) -> Bool { cleanTitle(doc.title).isEmpty }

    /// A human title, never empty: the server's display title, the cleaned title, the reference or
    /// series, else a plain name for the kind of document ("Law Commission report, 2010").
    static func tidyTitle(_ doc: LibraryDoc) -> String {
        if let display = truthy(doc.displayTitle) {
            let cleaned = cleanTitle(display)
            return cleaned.isEmpty ? display : cleaned
        }
        let t = cleanTitle(doc.title)
        if !t.isEmpty { return t }
        if let reference = truthy(doc.reference) { return reference }
        if let series = truthy(doc.series) {
            return series + (truthy(doc.volume).map { ", vol. \($0)" } ?? "")
        }
        let name = theme(doc.category).untitled
        if let year = doc.year, year != 0 { return "\(name), \(year)" }
        return name
    }

    // MARK: - Dates and counts

    private static let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    /// `1979-05-04` → `4 May 1979`; anything else comes back as given.
    static func fmtDay(_ iso: String?) -> String {
        guard let iso, let g = Pattern("^([0-9]{4})-([0-9]{2})-([0-9]{2})").groups(iso),
              let y = g[1], let m = g[2].flatMap({ Int($0) }), let d = g[3].flatMap({ Int($0) })
        else { return iso ?? "" }
        let month = (1...12).contains(m) ? months[m - 1] : ""
        return "\(d) \(month) \(y)"
    }

    /// `2,71,480` — `toLocaleString('en-IN')`.
    static func fmtCount(_ n: Int?) -> String {
        guard let n else { return "" }
        return DisplayText.grouped(n)
    }

    static func fmtCount(_ n: Double) -> String {
        guard n.isFinite else { return "" }
        return JSCompat.indianNumber(n)
    }

    /// A decision dated after today in India — a scraper's error, never a fact.
    static func isFutureDate(_ iso: String?, today: String = WireDate.todayKey()) -> Bool {
        guard let iso, Pattern("^[0-9]{4}-[0-9]{2}-[0-9]{2}").test(iso) else { return false }
        return String(iso.prefix(10)) > today
    }

    // MARK: - Covers and cards

    /// What a typographic cover prints.
    struct CoverFields: Equatable, Sendable {
        var kicker: String
        var title: String?
        var parties: [String]?
        var foot: [String]
    }

    private static func isCaseLike(_ doc: LibraryDoc) -> Bool {
        doc.category == LibraryCategoryKey.caseLaw.rawValue || doc.category == LibraryCategoryKey.tribunals.rawValue
    }

    /// A case name from its parties, else the "X vs Y" of its title (the cover's own rule).
    private static func coverParties(_ doc: LibraryDoc) -> [String]? {
        if let p = truthy(doc.petitioner), let r = truthy(doc.respondent) { return [p, r] }
        guard let g = Pattern("^(.+?)\\s+(?:vs\\.?|v\\.|versus)\\s+(.+)$", caseInsensitive: true)
            .groups(tidyTitle(doc)), let a = g[1], let b = g[2] else { return nil }
        return [a, b]
    }

    static func coverFields(_ doc: LibraryDoc) -> CoverFields {
        let theme = theme(doc.category)
        let year = truthy(doc.decidedOn).map { String($0.prefix(4)) } ?? (doc.year.flatMap { $0 == 0 ? nil : String($0) } ?? "")
        if isCaseLike(doc) {
            let parties = coverParties(doc)
            return CoverFields(
                kicker: truthy(doc.courtLabel) ?? theme.cap,
                title: parties == nil ? tidyTitle(doc) : nil,
                parties: parties,
                foot: [truthy(doc.decidedOn).map(fmtDay) ?? year, doc.neutralCitation ?? ""].filter { !$0.isEmpty })
        }
        let volume = truthy(doc.volume).map { "Vol. \($0)" } ?? ""
        let kicker = doc.category == LibraryCategoryKey.bareActs.rawValue
            ? (truthy(doc.jurisdiction) ?? "Central") : (truthy(doc.series) ?? theme.cap)
        return CoverFields(kicker: kicker, title: tidyTitle(doc), parties: nil,
                           foot: [volume, year].filter { !$0.isEmpty })
    }

    /// The facts a card prints under its title, most useful first.
    static func docMeta(_ doc: LibraryDoc) -> [String] {
        if isCaseLike(doc) {
            let when = truthy(doc.decidedOn).map(fmtDay) ?? doc.year.flatMap { $0 == 0 ? nil : String($0) }
            let number = truthy(doc.caseNumber).map { (truthy(doc.caseType).map { "\($0) " } ?? "") + $0 }
            return [truthy(doc.courtLabel), when, truthy(doc.neutralCitation) ?? number].compactMap { truthy($0) }
        }
        let jurisdiction = doc.category == LibraryCategoryKey.bareActs.rawValue
            ? (truthy(doc.jurisdiction) ?? "Central") : truthy(doc.jurisdiction)
        let series = truthy(doc.series).map { $0 + (truthy(doc.volume).map { ", vol. \($0)" } ?? "") }
        let year = doc.year.flatMap { $0 == 0 ? nil : String($0) }
        let related = doc.hasChildren.flatMap { $0 == 0 ? nil : "\($0) related" }
        return [jurisdiction, series, year, related].compactMap { truthy($0) }
    }

    /// A document opens as text (the judgment reader) or as a PDF.
    static func isTextDoc(_ doc: LibraryDoc) -> Bool {
        doc.render == "html" || doc.render == "text" || doc.ext == ".txt" || doc.ext == ".html"
    }

    /// What VoiceOver reads for a card: its title and its facts.
    static func accessibilityLabel(_ doc: LibraryDoc) -> String {
        let title = isCaseLike(doc) ? caseTitleText(doc) : (doc.category == LibraryCategoryKey.bareActs.rawValue ? actTitle(doc) : tidyTitle(doc))
        let meta = docMeta(doc)
        return meta.isEmpty ? title : "\(title). \(meta.joined(separator: ", "))"
    }

    // MARK: - Courts and cases

    struct Court: Equatable, Sendable {
        let key: String
        let name: String
        let short: String
        let mono: String
        let ink: String
        let inkDark: String
    }

    private static let courts: [String: (name: String, short: String, mono: String, ink: String, inkDark: String)] = [
        "supremecourt": ("Supreme Court of India", "Supreme Court", "SC", "#7A1F2B", "#F2A7B0"),
        "scorders": ("Supreme Court — daily orders", "SC orders", "SC", "#8A3A1C", "#F2B593"),
        "allahabad": ("Allahabad High Court", "Allahabad HC", "All", "#2D5E3A", "#9FD5AA"),
        "bombay": ("Bombay High Court", "Bombay HC", "Bom", "#1E4C7A", "#A3C6EC"),
        "kolkata": ("Calcutta High Court", "Calcutta HC", "Cal", "#653A7D", "#D5B2E6"),
        "delhi": ("Delhi High Court", "Delhi HC", "Del", "#17605F", "#8FD6D3"),
        "karnataka": ("Karnataka High Court", "Karnataka HC", "Kar", "#7C5A0E", "#E8C878"),
        "chennai": ("Madras High Court", "Madras HC", "Mad", "#8A2C5C", "#F0AACB"),
    ]

    /// Courts in rail order: the Supreme Court first, then the High Courts A–Z.
    static let courtOrder = ["supremecourt", "scorders", "allahabad", "bombay", "kolkata", "delhi", "karnataka", "chennai"]

    static func courtInfo(_ key: String?, label: String? = nil) -> Court {
        let k = key ?? ""
        if let c = courts[k] {
            return Court(key: k, name: c.name, short: c.short, mono: c.mono, ink: c.ink, inkDark: c.inkDark)
        }
        let name = truthy(label) ?? "Court"
        let stripped = JSCompat.trim(Pattern("High Court|Court|of|the", caseInsensitive: true).replaceAll(name, ""))
        let mono = JSCompat.prefixUTF16(stripped, 3)
        return Court(
            key: k, name: name,
            short: Pattern("High Court", caseInsensitive: true).replaceFirst(name, "HC"),
            mono: mono.isEmpty ? "§" : mono, ink: "#2B4373", inkDark: "#A9BDEB")
    }

    /// `/facets` courts in rail order; unknown keys last, A–Z.
    static func orderCourts(_ list: [LibraryFacetOption]) -> [LibraryFacetOption] {
        func rank(_ v: String) -> Int { courtOrder.firstIndex(of: v) ?? 99 }
        return JSCompat.stableSorted(list) { a, b in
            let r = rank(a.value) - rank(b.value)
            if r != 0 { return r }
            return a.displayLabel < b.displayLabel ? -1 : (a.displayLabel > b.displayLabel ? 1 : 0)
        }
    }

    private static let smallWords = Pattern("^(of|and|the|in|for|to|on|by|or|an|a|at|through|thr|vs|v)$", caseInsensitive: true)

    /// A party's name as the file name left it → as a law report prints it.
    static func tidyParty(_ name: String?) -> String {
        var s = JSCompat.trim(JSCompat.collapse(name ?? ""))
        if s.isEmpty { return "" }
        s = Pattern("^M/?S\\.?\\s+(?=\\S)", caseInsensitive: true).replaceFirst(s, "M/s ")
        s = Pattern("^M/?S(?=[A-Z][a-z])").replaceFirst(s, "M/s ")
        s = Pattern("\\bM/S\\b").replaceAll(s, "M/s")
        s = Pattern("\\b(Mr|Mrs|Dr|Smt|Sri|Shri|Ms)(?=[A-Z][a-z])").replaceAll(s) { g, _ in (g[1] ?? "") + " " }
        s = Pattern("\\b([SDW])O\\s+(?=[A-Z])").replaceAll(s) { g, _ in (g[1] ?? "").lowercased() + "/o " }
        s = Pattern("(^|[\\s(&])([A-Z]{1,3})(?=[A-Z][a-z]{2,})").replaceAll(s) { g, _ in
            (g[1] ?? "") + (g[2] ?? "").map(String.init).joined(separator: ".") + ". "
        }
        s = JSCompat.trim(JSCompat.collapse(s))
        if s.utf16.count > 6, s == s.uppercased(), Pattern("[A-Z]{3}").test(s) {
            s = Pattern("\\b([a-z])([a-z']*)").replaceAll(s.lowercased()) { g, offset in
                let m = g[0] ?? ""
                return offset > 0 && smallWords.test(m) ? m : (g[1] ?? "").uppercased() + (g[2] ?? "")
            }
        }
        s = Pattern("(\\s)(Of|And|The|In|For|To|On|By|At)(?=\\s)").replaceAll(s) { g, _ in
            (g[1] ?? "") + (g[2] ?? "").lowercased()
        }
        let cut = Pattern(
            "(?:\\s+(?:&|and|the|of|through|thr|by|rep|represented|vs\\.?|v\\.|versus))+\\.?$",
            caseInsensitive: true).replaceFirst(s, "")
        if cut != s, cut.utf16.count > 2 { s = cut + "…" }
        return s
    }

    private static let versus = Pattern("\\s+(?:vs\\.?|v\\.|v/s\\.?|versus)\\s+", caseInsensitive: true)

    /// `[petitioner, respondent]` tidied, from the fields or from an "A vs B" title.
    static func caseParties(petitioner: String?, respondent: String?, title: String?) -> [String]? {
        if let p = truthy(petitioner), let r = truthy(respondent) { return [tidyParty(p), tidyParty(r)] }
        let t = Pattern("\\s+on\\s+[0-9]{1,2}\\s+\\w+,?\\s+[0-9]{4}\\s*$", caseInsensitive: true)
            .replaceFirst(title ?? "", "")
        let parts = versus.split(t)
        if parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty { return [tidyParty(parts[0]), tidyParty(parts[1])] }
        return nil
    }

    static func caseParties(_ doc: LibraryDoc) -> [String]? {
        caseParties(petitioner: doc.petitioner, respondent: doc.respondent, title: doc.title)
    }

    /// `Seethamma v. State of Karnataka` — plain text, for a row, a copy and VoiceOver.
    static func caseTitleText(_ doc: LibraryDoc, header: LibraryJudgmentHeader? = nil) -> String {
        if let header, let p = caseParties(petitioner: header.petitioner, respondent: header.respondent, title: header.title) {
            return "\(p[0]) v. \(p[1])"
        }
        if let p = caseParties(doc) { return "\(p[0]) v. \(p[1])" }
        return tidyParty(truthy(header?.title) ?? truthy(doc.title) ?? "Untitled judgment")
    }

    /// `Civil Appeal No. 7710 of 2012`, or empty.
    static func caseNumberText(caseType: String?, caseNumber: String?) -> String {
        var type = JSCompat.trim(JSCompat.collapse(caseType ?? ""))
        if type.utf16.count > 34, !Pattern("^arising", caseInsensitive: true).test(type) { type = "" }
        let num = JSCompat.trim(caseNumber ?? "")
        if type.isEmpty && num.isEmpty { return "" }
        if num.isEmpty { return type }
        if type.isEmpty { return "No. \(num)" }
        if Pattern("arising|in\\s*$", caseInsensitive: true).test(type) { return "\(type) No. \(num)" }
        return "\(type) " + (Pattern("^no\\.?\\s", caseInsensitive: true).test(num) ? num : "No. \(num)")
    }

    static func caseNumberText(_ doc: LibraryDoc) -> String {
        caseNumberText(caseType: doc.caseType, caseNumber: doc.caseNumber)
    }

    /// `A v. B, (2012) 10 SCC 409 (Supreme Court, 31 Oct 2012)` (`citationLine`, `readerModel.js`).
    static func citationLine(_ doc: LibraryDoc, header: LibraryJudgmentHeader? = nil) -> String {
        let title = caseTitleText(doc, header: header)
        let headerNumber = header.map { caseNumberText(caseType: $0.caseType, caseNumber: $0.caseNumber) }
        let cite = truthy(header?.neutralCitation) ?? truthy(doc.neutralCitation)
            ?? truthy(header?.citations?.first) ?? truthy(headerNumber) ?? truthy(caseNumberText(doc))
        let court = courtInfo(truthy(header?.court) ?? doc.court, label: truthy(header?.courtLabel) ?? doc.courtLabel).short
        let day = truthy(header?.decidedOn) ?? truthy(doc.decidedOn)
        let year = (header?.year).flatMap { $0 == 0 ? nil : $0 } ?? doc.year.flatMap { $0 == 0 ? nil : $0 }
        let when = day.map(fmtDay) ?? year.map(String.init)
        let tail = [court, when].compactMap { truthy($0) }.joined(separator: ", ")
        return title + (cite.map { ", \($0)" } ?? "") + (tail.isEmpty ? "" : " (\(tail))")
    }

    // MARK: - Acts

    /// Tab keys in the catalogue's order.
    static let tabOrder = ["act", "rules", "regulations", "notifications", "orders", "ordinances", "schemes",
                           "bills", "circulars", "amendments", "editions", "related"]

    private static let tabNoun: [String: (String, String)] = [
        "rules": ("rule", "rules"), "regulations": ("regulation", "regulations"),
        "notifications": ("notification", "notifications"), "orders": ("order", "orders"),
        "ordinances": ("ordinance", "ordinances"), "schemes": ("scheme", "schemes"),
        "bills": ("bill", "bills"), "circulars": ("circular", "circulars"),
        "amendments": ("amendment", "amendments"), "editions": ("other edition", "other editions"),
        "related": ("related Act", "related Acts"),
    ]

    /// The "Contains" filters of the Acts index (`has=`), most asked-for first.
    static let hasFilters: [(key: String, label: String)] = [
        ("rules", "Rules"), ("regulations", "Regulations"), ("notifications", "Notifications"),
        ("amendments", "Amendments"), ("orders", "Orders"), ("schemes", "Schemes"),
    ]

    /// A title fit to print: scrape debris removed, the year set off by a comma.
    static func actTitle(_ doc: LibraryDoc) -> String {
        var raw = doc.title ?? ""
        raw = Pattern("^\\W*indian bare acts\\s+", caseInsensitive: true).replaceFirst(raw, "")
        raw = Pattern("^\\W*NDIAN\\b").replaceFirst(raw, "INDIAN")
        raw = Pattern("^[0-9](?=(?:the|THE|The|Dr)\\b|[A-Z]{2})").replaceFirst(raw, "")
        raw = Pattern("(?<=[A-Z])l(?=[A-Z])").replaceAll(raw, "I")
        let letters = raw.unicodeScalars.filter { ("A"..."Z").contains($0) || ("a"..."z").contains($0) }
        let upper = letters.filter { ("A"..."Z").contains($0) }.count
        let shouting = letters.count > 12 && Double(upper) / Double(letters.count) > 0.8 && raw != raw.uppercased()
        var copy = doc
        copy.title = shouting ? raw.uppercased() : raw
        var t = tidyTitle(copy)
        t = Pattern("\\s*\\(\\s*single document\\s*\\)", caseInsensitive: true).replaceAll(t, "")
        t = Pattern("\\s*\\(\\s*central act\\s*\\)", caseInsensitive: true).replaceAll(t, "")
        t = Pattern("\\s*[·•]\\s*").replaceAll(t, " ")
        t = t.replacingOccurrences(of: "_", with: " ")
        t = Pattern("\\s+'\\s+").replaceAll(t, " ")
        t = Pattern("\\b(Act|Code|Rules|Regulations?|Ordinance|Order|Scheme|Sanhita|Adhiniyam)\\s*[.,-]\\s*((?:1[789]|20)[0-9]{2})\\b")
            .replaceAll(t) { g, _ in "\(g[1] ?? ""), \(g[2] ?? "")" }
        t = Pattern("\\b(Act|Code|Rules|Regulations?|Ordinance|Sanhita|Adhiniyam)\\s+((?:1[789]|20)[0-9]{2})\\b")
            .replaceAll(t) { g, _ in "\(g[1] ?? ""), \(g[2] ?? "")" }
        t = Pattern("\\s+,").replaceAll(t, ",")
        t = Pattern("\\s{2,}").replaceAll(t, " ")
        t = JSCompat.trim(t)
        t = Pattern("(?<=\\s)(Of|And|The|In|For|To|On|By|Or|An|A)(?=\\s)").replaceAll(t) { g, _ in (g[0] ?? "").lowercased() }
        return t
    }

    private static let yearAfterWord = Pattern(
        "^(.*?\\b(?:Act|Code|Rules|Regulations?|Ordinance|Order|Scheme|Sanhita|Adhiniyam))\\s*,?\\s*(?:\\(?\\s*(?:Act\\s+)?No\\.?\\s*[0-9]+\\s+of\\s+)?((?:1[789]|20)[0-9]{2})\\b",
        caseInsensitive: true)
    private static let yearAtEnd = Pattern("^(.*?[^0-9.\\s,])(?:\\s*,\\s*|\\s+)((?:1[789]|20)[0-9]{2})\\s*$")

    /// The name and the year, printed apart on a cover.
    static func splitTitle(_ doc: LibraryDoc) -> (name: String, year: String) {
        let t = actTitle(doc)
        if let w = yearAfterWord.groups(t), let name = w[1], let year = w[2], name.utf16.count > 3 {
            return (name, year)
        }
        if let m = yearAtEnd.groups(t), let name = m[1], let year = m[2], name.utf16.count > 3 {
            return (Pattern("[\\s,]+$").replaceFirst(name, ""), year)
        }
        return (t, doc.year.flatMap { $0 == 0 ? nil : String($0) } ?? "")
    }

    private static let repealedPattern = Pattern("\\(\\s*rep\\.|\\brepealed\\b|\\bomitted\\b", caseInsensitive: true)

    static func isRepealed(_ doc: LibraryDoc) -> Bool {
        doc.repealed == true || repealedPattern.test(doc.title ?? "")
    }

    static func isRepealed(title: String) -> Bool { repealedPattern.test(title) }

    struct Jurisdiction: Equatable, Sendable {
        let value: String
        let label: String
        let short: String
        let central: Bool
    }

    private static let shortJurisdiction = [
        "Dadra and Nagar Haveli and Daman and Diu": "DNH & Daman and Diu",
        "Andaman and Nicobar Islands": "Andaman & Nicobar",
        "Jammu and Kashmir": "Jammu & Kashmir",
    ]

    static func jurisdictionOf(_ doc: LibraryDoc) -> Jurisdiction {
        guard let v = truthy(doc.jurisdiction), v != "none" else {
            return Jurisdiction(value: "none", label: "Unspecified", short: "", central: false)
        }
        return Jurisdiction(value: v, label: v, short: shortJurisdiction[v] ?? v, central: v == "Central")
    }

    static let stateCloths = ["#1F3A5F", "#1E4D3B", "#1D4B55", "#4A2747", "#5A3A1E", "#2F3A4A", "#3B3570",
                              "#5B2E1F", "#2F5D50", "#3F2F5A"]
    static let unspecifiedCloth = "#3A3F5C"

    /// An Act's cloth: oxblood for Central Acts, one colour per State.
    static func actCloth(_ doc: LibraryDoc) -> String {
        let j = jurisdictionOf(doc)
        if j.central {
            let c = theme(LibraryCategoryKey.bareActs.rawValue).cloth
            return c[Int(hashOf(String(doc.id)) % UInt32(c.count))]
        }
        if j.value == "none" { return unspecifiedCloth }
        return stateCloths[Int(hashOf(j.value) % UInt32(stateCloths.count))]
    }

    /// `["9 rules", "25 amendments"]` — instruments only, unless `withEditions`.
    static func countParts(_ tabCounts: [String: Int]?, withEditions: Bool = false, first: String? = nil) -> [String] {
        guard let tabCounts else { return [] }
        var order = tabOrder
        if let first, tabOrder.contains(first) { order = [first] + tabOrder.filter { $0 != first } }
        return order.compactMap { k -> String? in
            guard k != "act", withEditions || (k != "editions" && k != "related"),
                  let n = tabCounts[k], n > 0, let noun = tabNoun[k] else { return nil }
            return "\(DisplayText.grouped(n)) \(n == 1 ? noun.0 : noun.1)"
        }
    }

    /// `1.4 MB` — an Act's size (`fmtSize`, `actText.js`).
    static func actSize(_ bytes: Int?) -> String {
        guard let bytes, bytes > 0 else { return "" }
        let n = Double(bytes)
        if n < 1024 * 1024 { return "\(max(1, Int(JSCompat.round(n / 1024)))) KB" }
        return "\(toFixed(n / (1024 * 1024), n < 10 * 1024 * 1024 ? 1 : 0)) MB"
    }

    /// Where a copy of an Act came from.
    static func copySource(_ doc: LibraryDoc) -> String {
        if let j = truthy(doc.jurisdiction), doc.jurisdictionInferred != true {
            return j == "Central" ? "India Code" : "\(j) copy"
        }
        return "India Code, 2026 scrape"
    }

    /// What an Act page's first tab is called.
    static func actTabLabel(_ doc: LibraryDoc, kind: String?) -> String {
        if kind == "amendments" { return "Amending Acts" }
        let t = (doc.title ?? "").lowercased()
        if Pattern("constitution of india").test(t) { return "The Constitution" }
        if Pattern("\\bsanhita\\b").test(t) { return "The Sanhita" }
        if Pattern("\\badhiniyam\\b").test(t) { return "The Adhiniyam" }
        if Pattern("\\bcode\\b").test(t), !Pattern("\\bact\\b").test(t) { return "The Code" }
        if kind == "orphan", let type = truthy(doc.docType), type != "act" { return "The document" }
        if Pattern("\\bregulation\\b").test(t), !Pattern("\\bact\\b").test(t) { return "The Regulation" }
        return "The Act"
    }

    /// The kind of volume, for a cover's top line.
    static func actKicker(_ doc: LibraryDoc) -> String {
        if doc.kind == "amendments" { return "Amending Acts" }
        if let alias = doc.aliases?.first { return alias }
        if let type = truthy(doc.docType), type != "act" {
            let names = ["rules": "Rules", "regulation": "Regulations", "notification": "Notification",
                         "order": "Order", "ordinance": "Ordinance", "scheme": "Scheme",
                         "circular": "Circular", "bill": "Bill"]
            return names[type] ?? "Instrument"
        }
        let j = jurisdictionOf(doc)
        if j.central { return "Bare Act" }
        return j.value == "none" ? "Act" : "State Act"
    }

    /// The most recent instrument of a list; `nil` when they share a year or there is one.
    static func latestID(_ docs: [LibraryDoc]) -> Int? {
        guard docs.count >= 2 else { return nil }
        var best: LibraryDoc?
        for d in docs {
            if let y = d.year, y != 0, best == nil || y > (best?.year ?? 0) { best = d }
        }
        guard let best else { return nil }
        return docs.filter { $0.year == best.year }.count == 1 ? best.id : nil
    }

    // MARK: - Books

    private static func volumeNumber(_ doc: LibraryDoc) -> Int? {
        if let n = doc.volumeNo { return n }
        let s = Pattern("^vol(ume)?[.\\s-]*", caseInsensitive: true).replaceFirst(JSCompat.trim(doc.volume ?? ""), "")
        guard let g = Pattern("^([0-9]{1,5})").groups(s), let d = g[1] else { return nil }
        return Int(d)
    }

    private static func volumeText(_ doc: LibraryDoc) -> String {
        let stripped = Pattern("^vol(ume)?[.\\s-]*", caseInsensitive: true).replaceFirst(doc.volume ?? "", "")
        if let n = volumeNumber(doc), Pattern("^[0-9]").test(stripped) { return String(n) }
        var raw = Pattern("^vol(ume)?[.\\s-]*", caseInsensitive: true).replaceFirst(JSCompat.trim(doc.volume ?? ""), "")
        raw = Pattern("(st|nd|rd|th)$", caseInsensitive: true).replaceFirst(raw, "")
        return raw.isEmpty ? "" : JSCompat.prefixUTF16(raw.uppercased(), 7)
    }

    /// The call-number label of a cover: `Vol. 12` over `1987`, `No. 277` over `2018`.
    static func volumeLabel(_ doc: LibraryDoc) -> (top: String, bottom: String)? {
        let year = doc.year.flatMap { $0 == 0 ? nil : String($0) } ?? ""
        if doc.category == LibraryCategoryKey.lawCommission.rawValue, let n = doc.reportNo, n != 0 {
            return ("No. \(n)", year)
        }
        if doc.category == LibraryCategoryKey.books.rawValue {
            let v = volumeText(doc)
            let issue = truthy(doc.issue).map { "No. \(JSCompat.prefixUTF16($0, 6))" }
            if !v.isEmpty { return ("Vol. \(v)", year.isEmpty ? (issue ?? "") : year) }
            if let issue { return (issue, year) }
        }
        return nil
    }

    /// `6.2 MB`, `2.5 GB` — a book's size (`fmtSize`, `bookFormat.js`).
    static func bookSize(_ bytes: Int?) -> String {
        guard let bytes, bytes > 0 else { return "" }
        let n = Double(bytes)
        let mb = 1024.0 * 1024
        if n >= mb * 1024 { return "\(toFixed(n / (mb * 1024), 1)) GB" }
        if n >= mb { return "\(toFixed(n / mb, n >= 100 * mb ? 0 : 1)) MB" }
        return "\(max(1, Int(JSCompat.round(n / 1024)))) KB"
    }

    static func yearSpan(_ min: Int?, _ max: Int?) -> String {
        let a = min.flatMap { $0 == 0 ? nil : $0 }
        let b = max.flatMap { $0 == 0 ? nil : $0 }
        if a == nil && b == nil { return "" }
        if b == nil || a == b { return String(a ?? b ?? 0) }
        if a == nil { return String(b ?? 0) }
        return "\(a ?? 0)–\(b ?? 0)"
    }

    /// A series name that shouts, title-cased.
    static func seriesName(_ name: String?) -> String {
        let s = name ?? ""
        if s.utf16.count < 6 || s != s.uppercased() { return s }
        var t = Pattern("(^|\\s)(\\p{L})").replaceAll(s.lowercased()) { g, _ in (g[1] ?? "") + (g[2] ?? "").uppercased() }
        t = Pattern("\\s(Of|And|The|In|For|To|On|By)\\b").replaceAll(t) { g, _ in (g[0] ?? "").lowercased() }
        return t
    }

    /// The facts under a cover: when, the series, the size.
    static func captionMeta(_ doc: LibraryDoc, withSeries: Bool = true, withSize: Bool = false) -> [String] {
        var out: [String] = []
        let when = truthy(doc.decidedOn).map(fmtDay) ?? truthy(doc.dateFromTitle).map(fmtDay)
            ?? doc.year.flatMap { $0 == 0 ? nil : String($0) } ?? ""
        if !when.isEmpty { out.append(when) }
        if withSeries, let series = truthy(doc.series) { out.append(seriesName(series)) }
        if withSize, let size = doc.fileSize, size > 0 { out.append(bookSize(size)) }
        return out
    }

    /// The reference a regulator order or tribunal decision leads with.
    static func referenceLine(_ doc: LibraryDoc) -> String {
        let ref = truthy(doc.displayRef) ?? truthy(doc.reference)
        let when = truthy(doc.decidedOn).map(fmtDay)
        return [ref, when].compactMap { truthy($0) }.joined(separator: " · ")
    }

    /// A volume's caption inside its own series: `Vol. 1, Issue 615`.
    static func volumeTitle(_ doc: LibraryDoc, series: String? = nil) -> String {
        let title = tidyTitle(doc)
        let s = series ?? doc.series ?? ""
        let ns = title as NSString
        var rest = !s.isEmpty && title.lowercased().hasPrefix(s.lowercased()) && ns.length >= (s as NSString).length
            ? ns.substring(from: (s as NSString).length) : title
        if let year = doc.year, year != 0 {
            rest = Pattern("\\s*\\(?\\b\(year)\\b\\)?\\s*$").replaceFirst(rest, "")
        }
        rest = Pattern("^[\\s,.:;–—-]+").replaceFirst(rest, "")
        rest = Pattern("\\bvol(?:ume)?[.\\s-]*0*([0-9]+|[ivxlcdm]+)\\b", caseInsensitive: true).replaceFirst(rest) { g, _ in
            let v = g[1] ?? ""
            return "Vol. " + (Pattern("^[0-9]").test(v) ? v : v.uppercased())
        }
        rest = Pattern("\\bissue\\s*no\\.?[\\s-]*0*(\\w+)", caseInsensitive: true).replaceFirst(rest) { g, _ in "Issue \(g[1] ?? "")" }
        rest = JSCompat.trim(JSCompat.collapse(rest))
        if !rest.isEmpty { return rest }
        if let v = volumeLabel(doc) { return v.top }
        let named = seriesName(s)
        return named.isEmpty ? title : named
    }

    /// One kind of regulator paper as a single document's label.
    static let kindOne: [String: String] = [
        "adjudication": "Adjudication order", "settlement": "Settlement order",
        "recovery": "Recovery proceedings", "order": "Order", "circular": "Circular / direction",
        "regulation": "Regulation / consultation", "speech": "Speech or notice", "fund": "Offer document",
        "appeal": "RTI appeal", "court": "Court matter", "case": "Antitrust case", "act": "Act or bill",
        "committee": "Committee report", "comparison": "Summary", "amendments": "Amendment notice",
    ]

    private static func volumeOrder(_ a: LibraryDoc, _ b: LibraryDoc) -> Int {
        let va = volumeNumber(a)
        let vb = volumeNumber(b)
        if let va, let vb, va != vb { return va - vb }
        if (va == nil) != (vb == nil) { return va == nil ? 1 : -1 }
        if (a.year ?? 0) != (b.year ?? 0) { return (a.year ?? 9999) - (b.year ?? 9999) }
        switch tidyTitle(a).compare(tidyTitle(b), options: [.numeric, .caseInsensitive]) {
        case .orderedAscending: return -1
        case .orderedDescending: return 1
        case .orderedSame: return 0
        }
    }

    struct Decade: Equatable, Sendable, Identifiable {
        let key: String
        let label: String
        let items: [LibraryDoc]
        var id: String { key }
    }

    /// Volumes by decade, oldest first, thin decades merged with a neighbour; undated last.
    static func groupByDecade(_ docs: [LibraryDoc], thisYear: Int = Calendar(identifier: .gregorian).component(.year, from: Date())) -> [Decade] {
        var groups: [Int: [LibraryDoc]] = [:]
        var undated: [LibraryDoc] = []
        for d in docs {
            if let y = d.year, y > 1500, y <= thisYear + 1 {
                groups[(y / 10) * 10, default: []].append(d)
            } else {
                undated.append(d)
            }
        }
        struct Run { var key: String; var from: Int; var to: Int; var items: [LibraryDoc] }
        var runs: [Run] = []
        for k in groups.keys.sorted() {
            let items = JSCompat.stableSorted(groups[k] ?? [], by: volumeOrder)
            if var prev = runs.last, prev.items.count < 4 || items.count < 2 {
                prev.items = JSCompat.stableSorted(prev.items + items, by: volumeOrder)
                prev.to = k
                runs[runs.count - 1] = prev
                continue
            }
            runs.append(Run(key: String(k), from: k, to: k, items: items))
        }
        var out = runs.map { r -> Decade in
            if r.from == r.to { return Decade(key: r.key, label: "\(r.from)s", items: r.items) }
            let ys = r.items.compactMap(\.year)
            return Decade(key: r.key, label: "\(ys.min() ?? r.from)–\(ys.max() ?? r.to)", items: r.items)
        }
        if !undated.isEmpty {
            out.append(Decade(key: "undated", label: "Undated volumes", items: JSCompat.stableSorted(undated, by: volumeOrder)))
        }
        return out
    }

    // MARK: - Helpers

    /// A `#RRGGBB` of this file as a colour.
    static func color(_ hex: String) -> PaletteColor {
        PaletteColor(hex: UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0)
    }

    /// JavaScript truthiness for an optional string: `nil` and `""` are false.
    static func truthy(_ s: String?) -> String? {
        guard let s, !s.isEmpty else { return nil }
        return s
    }

    /// `Number.prototype.toFixed`: ties round up.
    static func toFixed(_ x: Double, _ digits: Int) -> String {
        let p = pow(10.0, Double(digits))
        let n = JSCompat.round(x * p)
        if digits == 0 { return String(Int(n)) }
        let whole = Int(n) / Int(p)
        let frac = Int(n) % Int(p)
        let fracText = String(frac)
        return "\(whole)." + String(repeating: "0", count: max(0, digits - fracText.count)) + fracText
    }

    private static func capitalizeFirst(_ s: String) -> String {
        guard let first = s.first else { return s }
        return first.uppercased() + s.dropFirst()
    }

    /// A regular expression with JavaScript's habits where they matter here: searched over UTF-16,
    /// a group that took no part read as `nil`, and a replacement given the match's groups.
    struct Pattern: @unchecked Sendable {
        let regex: NSRegularExpression

        init(_ pattern: String, caseInsensitive: Bool = false) {
            // A pattern here is a literal in this file; a typo is a programming error the golden
            // tests catch.
            regex = try! NSRegularExpression(pattern: pattern, options: caseInsensitive ? [.caseInsensitive] : [])
        }

        private func range(_ s: String) -> NSRange { NSRange(location: 0, length: (s as NSString).length) }

        func test(_ s: String) -> Bool { regex.firstMatch(in: s, range: range(s)) != nil }

        func groups(_ s: String) -> [String?]? {
            guard let m = regex.firstMatch(in: s, range: range(s)) else { return nil }
            return groups(of: m, in: s as NSString)
        }

        private func groups(of m: NSTextCheckingResult, in ns: NSString) -> [String?] {
            (0..<m.numberOfRanges).map { i in
                let r = m.range(at: i)
                return r.location == NSNotFound ? nil : ns.substring(with: r)
            }
        }

        func replaceAll(_ s: String, _ literal: String) -> String { replace(s, all: true) { _, _ in literal } }
        func replaceFirst(_ s: String, _ literal: String) -> String { replace(s, all: false) { _, _ in literal } }
        func replaceAll(_ s: String, _ f: ([String?], Int) -> String) -> String { replace(s, all: true, f) }
        func replaceFirst(_ s: String, _ f: ([String?], Int) -> String) -> String { replace(s, all: false, f) }

        private func replace(_ s: String, all: Bool, _ f: ([String?], Int) -> String) -> String {
            let ns = s as NSString
            let matches = all ? regex.matches(in: s, range: range(s)) : regex.firstMatch(in: s, range: range(s)).map { [$0] } ?? []
            var out = ""
            var last = 0
            for m in matches {
                out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
                out += f(groups(of: m, in: ns), m.range.location)
                last = m.range.location + m.range.length
            }
            out += ns.substring(from: last)
            return out
        }

        /// `String.prototype.split` with this expression (no capture groups).
        func split(_ s: String) -> [String] {
            let ns = s as NSString
            var out: [String] = []
            var last = 0
            for m in regex.matches(in: s, range: range(s)) where m.range.length > 0 {
                out.append(ns.substring(with: NSRange(location: last, length: m.range.location - last)))
                last = m.range.location + m.range.length
            }
            out.append(ns.substring(from: last))
            return out
        }
    }
}
