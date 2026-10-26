import Foundation

/// Derived facts about a matter and about tracked court cases shown as matters — a port of the
/// platform's `src/components/projects/projectMeta.js`, `src/components/matters/trackedCases.js`,
/// `src/components/projects/trackCase.js` and the naming helpers of
/// `src/components/lookup/lookupModel.js`.
enum MatterMeta {

    typealias BannerPreset = MatterVocabulary.BannerPreset
    typealias OurSide = MatterVocabulary.OurSide
    typealias ProjectStatus = MatterVocabulary.ProjectStatus

    // MARK: - projectMeta.js

    private static let presetForColor: [String: BannerPreset] = [
        "indigo": .indigo, "violet": .indigo, "fuchsia": .wine, "rose": .wine,
        "amber": .gold, "green": .forest, "teal": .teal, "sky": .navy,
    ]

    /// `bannerPresetOf`: the matter's preset; for none (or `image`), the preset nearest its folder
    /// colour; navy without either.
    static func bannerPreset(banner: String?, color: String?) -> BannerPreset {
        if let banner, let preset = BannerPreset(rawValue: banner) { return preset }
        return color.flatMap { presetForColor[$0] } ?? .navy
    }

    /// `practiceAreaLabel`: the label, or the key as written; "" for none.
    static func practiceAreaLabel(_ key: String?) -> String {
        MatterVocabulary.PracticeArea.label(for: key)
    }

    /// projectMeta's `ourSideLabel`: the label ("Other" included), or free text as typed.
    /// `MatterRecord.sideLabelForTitle` is the cause title's reading.
    static func sideLabel(_ side: String?) -> String {
        OurSide.label(for: side)
    }

    /// `caseRefOf`: "W.P.(C) 4412/2025" as the registry prints it; the CNR without a number.
    static func caseRef(caseNumber: String?, caseType: String?, caseYear: String?, cnr: String?) -> String {
        if let caseNumber, !caseNumber.isEmpty {
            let type = (caseType?.isEmpty == false) ? "\(caseType!) " : ""
            let year = (caseYear?.isEmpty == false) ? "/\(caseYear!)" : ""
            return "\(type)\(caseNumber)\(year)"
        }
        return cnr ?? ""
    }

    /// `activityAt`: when the matter last moved — the latest of `updated_at`, `created_at` and a
    /// `last_activity` that is not in the future; nil when none can be read.
    static func activityAt(updated: String?, created: String?, lastActivity: String?, now: Date = Date()) -> Date? {
        func ms(_ v: String?) -> Double { JSCompat.parseDate(v) ?? 0 }
        let last = ms(lastActivity)
        let nowMs = now.timeIntervalSince1970 * 1000
        let best = max(ms(updated), ms(created), last > nowMs ? 0 : last)
        return best == 0 ? nil : Date(timeIntervalSince1970: best / 1000)
    }

    // MARK: - trackedCases.js

    /// Row ids of tracked cases in the Matters list carry this prefix.
    static let trackedPrefix = "case:"

    private static let disposedWords = MatterPattern("dispos|decided|dismiss|closed", caseInsensitive: true)

    /// `caseStatusKey`: the court's word for a case's state → the matter status it files under.
    static func caseStatusKey(_ status: String?) -> ProjectStatus {
        disposedWords.test(status ?? "") ? .disposed : .active
    }

    /// `bannerForCase`: a preset per case id (FNV-1a over its code points), so a tracked case
    /// wears the same banner on every visit and keeps it once opened as a matter.
    static func bannerForCase(_ caseID: String) -> BannerPreset {
        var h: UInt32 = 2_166_136_261
        for scalar in caseID.unicodeScalars {
            h = (h ^ scalar.value) &* 16_777_619
        }
        return BannerPreset.allCases[Int(h % UInt32(BannerPreset.allCases.count))]
    }

    /// `matterByCase`: case id → the matter made for it; when two link one case the oldest
    /// `created_at` (compared as text, as SQLite does) wins.
    static func matterByCase(_ projects: [(id: String, linkedCaseID: String?, createdAt: String?)]) -> [String: String] {
        var map: [String: (id: String, created: String)] = [:]
        for p in projects {
            guard let key = p.linkedCaseID, !key.isEmpty else { continue }
            let created = p.createdAt ?? ""
            if let had = map[key], !created.utf16.lexicographicallyPrecedes(had.created.utf16) { continue }
            map[key] = (p.id, created)
        }
        return map.mapValues(\.id)
    }

    /// `CATEGORY_LABEL` of `src/lib/courts.js`: a court type in words.
    static let courtCategoryLabels: [String: String] = [
        "sc": "Supreme Court", "hc": "High Court", "nclt": "NCLT", "nclat": "NCLAT",
        "district": "District Court", "tribunal": "Tribunal", "forum": "Forum",
    ]

    /// A tracked case, as much of it as a Matters row reads.
    struct TrackedCase: Equatable, Sendable {
        var id: String
        var title: String?
        var parties: String?
        var status: String?
        var courtName: String?
        var courtType: String?
        var caseType: String?
        var caseNumber: String?
        var caseYear: String?
        var cnr: String?
        var diaryNumber: String?
        var stage: String?
        var nextHearingDate: String?
        var teamName: String?
        var createdAt: String?

        init(id: String, title: String? = nil, parties: String? = nil, status: String? = nil, courtName: String? = nil,
             courtType: String? = nil, caseType: String? = nil, caseNumber: String? = nil, caseYear: String? = nil,
             cnr: String? = nil, diaryNumber: String? = nil, stage: String? = nil, nextHearingDate: String? = nil,
             teamName: String? = nil, createdAt: String? = nil) {
            self.id = id
            self.title = title
            self.parties = parties
            self.status = status
            self.courtName = courtName
            self.courtType = courtType
            self.caseType = caseType
            self.caseNumber = caseNumber
            self.caseYear = caseYear
            self.cnr = cnr
            self.diaryNumber = diaryNumber
            self.stage = stage
            self.nextHearingDate = nextHearingDate
            self.teamName = teamName
            self.createdAt = createdAt
        }
    }

    /// `trackedCaseRow`: a tracked case in the shape of a matter row.
    struct TrackedCaseRow: Equatable, Sendable {
        let id: String
        let caseID: String
        let name: String
        let status: ProjectStatus
        /// The court's own word ("Pending").
        let courtStatus: String
        let banner: BannerPreset
        let forumName: String
        let caseRef: String
        let caseType: String
        let caseNumber: String
        let caseYear: String
        let cnr: String
        let diaryNumber: String
        let parties: String
        let stage: String
        let nextHearingDate: String?
        /// The team's name when the case is shared with more than its owner.
        let sharedWith: String
        let createdAt: String?
    }

    private static func or(_ values: String?...) -> String {
        values.first { $0?.isEmpty == false }.flatMap { $0 } ?? ""
    }

    static func trackedCaseRow(_ k: TrackedCase, team: (name: String?, memberCount: Int)?) -> TrackedCaseRow {
        let numbered = caseRef(caseNumber: k.caseNumber, caseType: k.caseType, caseYear: k.caseYear, cnr: k.cnr)
        let ref = !numbered.isEmpty ? numbered : ((k.diaryNumber?.isEmpty == false) ? "Diary No. \(k.diaryNumber!)" : "")
        let name = (k.title?.isEmpty == false) ? CourtNames.tidy(k.title, title: true) : or(k.parties, ref, "Untitled case")
        var shared = ""
        if let team, team.memberCount > 1 { shared = or(team.name, k.teamName) }
        return TrackedCaseRow(
            id: trackedPrefix + k.id, caseID: k.id, name: name, status: caseStatusKey(k.status),
            courtStatus: k.status ?? "", banner: bannerForCase(k.id),
            forumName: or(k.courtName, k.courtType.flatMap { courtCategoryLabels[$0] }),
            caseRef: ref, caseType: k.caseType ?? "", caseNumber: k.caseNumber ?? "", caseYear: k.caseYear ?? "",
            cnr: k.cnr ?? "", diaryNumber: k.diaryNumber ?? "", parties: k.parties ?? "", stage: k.stage ?? "",
            nextHearingDate: (k.nextHearingDate?.isEmpty == false) ? k.nextHearingDate : nil,
            sharedWith: shared, createdAt: (k.createdAt?.isEmpty == false) ? k.createdAt : nil)
    }

    // MARK: - trackCase.js

    /// A court case picked in a search, under the keys `POST /save-case` takes (`casePayload`).
    struct CasePick: Equatable, Sendable {
        var courtType: String?
        var courtCode: String?
        var courtName: String?
        var caseType: String?
        var caseNumber: String?
        var caseYear: String?
        var cnr: String?
        var diaryNumber: String?
        var title: String?
        var parties: String?
        var judge: String?
        var status: String?
        var stage: String?
        var nextHearingDate: String?
        var scrapeRef: String?

        init(courtType: String? = nil, courtCode: String? = nil, courtName: String? = nil, caseType: String? = nil,
             caseNumber: String? = nil, caseYear: String? = nil, cnr: String? = nil, diaryNumber: String? = nil,
             title: String? = nil, parties: String? = nil, judge: String? = nil, status: String? = nil,
             stage: String? = nil, nextHearingDate: String? = nil, scrapeRef: String? = nil) {
            self.courtType = courtType
            self.courtCode = courtCode
            self.courtName = courtName
            self.caseType = caseType
            self.caseNumber = caseNumber
            self.caseYear = caseYear
            self.cnr = cnr
            self.diaryNumber = diaryNumber
            self.title = title
            self.parties = parties
            self.judge = judge
            self.status = status
            self.stage = stage
            self.nextHearingDate = nextHearingDate
            self.scrapeRef = scrapeRef
        }

        /// `casePayload`: the body `/save-case` takes — the CNR, or for courts that issue none the
        /// diary number, in `cnr`; blanks as nil.
        var payload: CasePick {
            func n(_ v: String?) -> String? { (v?.isEmpty == false) ? v : nil }
            var p = self
            p.cnr = n(cnr) ?? n(diaryNumber)
            p.diaryNumber = n(diaryNumber)
            p.parties = n(parties)
            p.judge = n(judge)
            p.status = n(status)
            p.stage = n(stage)
            p.nextHearingDate = n(nextHearingDate)
            p.scrapeRef = n(scrapeRef)
            return p
        }
    }

    /// `extIdOf`: the identity `/save-case` dedupes on — the CNR, else court|type|number|year.
    static func extID(of pick: CasePick) -> String {
        let body = pick.payload
        if let cnr = body.cnr { return cnr }
        return [body.courtCode, body.caseType, body.caseNumber, body.caseYear].map { $0 ?? "" }.joined(separator: "|")
    }

    /// `canon`: upper case, letters and digits only.
    static func canon(_ s: String?) -> String {
        String(String.UnicodeScalarView((s ?? "").uppercased().unicodeScalars.filter {
            (48...57).contains($0.value) || (65...90).contains($0.value)
        }))
    }

    /// A case the user already tracks, as `findTrackedCase` compares it.
    struct TrackedCaseCandidate: Equatable, Sendable {
        var id: String
        var teamID: String?
        /// The stored `ext_id`; nil computes it from the fields below, as the server computed it on save.
        var extID: String?
        var cnr: String?
        var diaryNumber: String?
        var caseNumber: String?
        var caseYear: String?
        var caseType: String?
        var courtCode: String?
        var courtName: String?

        init(id: String, teamID: String? = nil, extID: String? = nil, cnr: String? = nil, diaryNumber: String? = nil,
             caseNumber: String? = nil, caseYear: String? = nil, caseType: String? = nil, courtCode: String? = nil,
             courtName: String? = nil) {
            self.id = id
            self.teamID = teamID
            self.extID = extID
            self.cnr = cnr
            self.diaryNumber = diaryNumber
            self.caseNumber = caseNumber
            self.caseYear = caseYear
            self.caseType = caseType
            self.courtCode = courtCode
            self.courtName = courtName
        }

        var effectiveExtID: String {
            if let extID { return extID }
            return MatterMeta.extID(of: CasePick(courtCode: courtCode, caseType: caseType, caseNumber: caseNumber,
                                                 caseYear: caseYear, cnr: cnr))
        }
    }

    /// `findTrackedCase`: the id of the tracked case that is this pick — by `ext_id`, then the
    /// CNR or diary number, then number + year + type in the same court — preferring a case in a
    /// team the user owns; nil when there is none (or the pick has no number and no CNR).
    static func findTrackedCase(_ pick: CasePick, in cases: [TrackedCaseCandidate], ownedTeamIDs: Set<String>) -> String? {
        let body = pick.payload
        guard body.cnr != nil || body.caseNumber?.isEmpty == false else { return nil }
        let ext = extID(of: body)
        let id = canon(body.cnr)
        var hits = cases.filter { !$0.effectiveExtID.isEmpty && $0.effectiveExtID == ext }
        if hits.isEmpty, !id.isEmpty {
            hits = cases.filter { canon($0.cnr) == id || canon($0.diaryNumber) == id }
        }
        if hits.isEmpty, body.caseNumber?.isEmpty == false {
            hits = cases.filter { c in
                canon(c.caseNumber) == canon(body.caseNumber) && canon(c.caseYear) == canon(body.caseYear)
                    && canon(c.caseType) == canon(body.caseType)
                    && ((body.courtCode?.isEmpty == false && canon(c.courtCode) == canon(body.courtCode))
                        || canon(c.courtName) == canon(body.courtName))
            }
        }
        return (hits.first { $0.teamID.map(ownedTeamIDs.contains) ?? false } ?? hits.first)?.id
    }

    // MARK: - lookupModel.js

    /// `caseNumberOf` (lookup): "W.P.(C) 12/2025".
    static func lookupCaseNumber(caseType: String?, caseNumber: String?, caseYear: String?) -> String {
        var number: String?
        if let caseNumber, !caseNumber.isEmpty {
            number = caseNumber + ((caseYear?.isEmpty == false) ? "/\(caseYear!)" : "")
        }
        return [caseType, number].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// `titleOf` (lookup): the cause title as a matter name, else the case number.
    static func lookupTitle(title: String?, caseType: String?, caseNumber: String?, caseYear: String?) -> String {
        if let title, !title.isEmpty { return CourtNames.tidy(title, title: true) }
        let number = lookupCaseNumber(caseType: caseType, caseNumber: caseNumber, caseYear: caseYear)
        return number.isEmpty ? "Untitled case" : number
    }

    private static let appealTypes = MatterPattern(
        "APPEAL|^(RFA|RSA|FAO|LPA|CRL ?A|CRA|CA|SA|FA|MFA|CMA|EFA|EXFA|OSA|AS|ITA|MAC ?APP|CO ?APP)\\b")
    private static let suitTypes = MatterPattern("SUIT|^(CS|OS|COS|TS|MS|SCS)\\b")

    /// `sideKeysFor`: the words a kind of proceeding uses for its two sides — a suit's plaintiff,
    /// an appeal's appellant, everything else a petitioner.
    static func sideKeys(caseType: String?) -> (OurSide, OurSide) {
        let t = JSCompat.trim(JSCompat.collapse((caseType ?? "").uppercased().replacingOccurrences(of: ".", with: "")))
        if appealTypes.test(t) { return (.appellant, .respondent) }
        if suitTypes.test(t) { return (.plaintiff, .defendant) }
        return (.petitioner, .respondent)
    }
}
