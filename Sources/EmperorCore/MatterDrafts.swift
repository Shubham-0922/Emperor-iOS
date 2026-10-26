import Foundation

/// The matter forms' drafts and the bodies they send — ports of the web's form state:
/// `draftFromRow` / `fieldsFromDraft` (`src/components/projects/shared.jsx`), and the task, ledger,
/// person and chronology forms of `src/components/projects/sections/`. Every draft value is text a
/// field can hold; the body is what the web would send for it, key for key.
enum MatterDrafts {

    // MARK: - The matter

    /// Edit matter details: every field a matter has.
    struct MatterForm: Equatable, Sendable {
        var id: String?
        var name = ""
        var client = ""
        var description = ""
        /// `other` for a matter whose forum nobody chose, as the server defaults it.
        var forumType = "other"
        var forumName = ""
        var caseType = ""
        var caseNumber = ""
        var caseYear = ""
        var cnr = ""
        var stage = ""
        var status = "active"
        var priority = "normal"
        /// `YYYY-MM-DD` or "".
        var nextHearingDate = ""
        var filingDate = ""
        var practiceArea = ""
        /// A vocabulary key, `other` (with `ourSideText`), or "".
        var ourSide = ""
        var ourSideText = ""
        var oppositeParty = ""
        /// A folder colour key, or nil for none.
        var color: String?
        /// A preset key, or `image`.
        var banner = MatterVocabulary.BannerPreset.navy.rawValue
        var linkedCaseID: String?
        /// `not_filed`, or "".
        var courtStatus = ""

        init() {}

        /// `draftFromRow`.
        init(_ p: Project) {
            id = p.id
            name = p.name ?? ""
            client = p.client ?? ""
            description = p.notes ?? ""
            forumType = (p.forumType?.isEmpty == false) ? p.forumType! : "other"
            forumName = p.forumName ?? ""
            caseType = p.caseType ?? ""
            caseNumber = p.caseNumber ?? ""
            caseYear = p.caseYear ?? ""
            cnr = p.cnr ?? ""
            stage = p.stage ?? ""
            status = (p.status?.isEmpty == false) ? p.status! : "active"
            priority = (p.priority?.isEmpty == false) ? p.priority! : "normal"
            nextHearingDate = String((p.nextHearingDateRaw ?? "").prefix(10))
            filingDate = String((p.filingDateRaw ?? "").prefix(10))
            practiceArea = p.practiceArea ?? ""
            let side = p.ourSide ?? ""
            let known = MatterVocabulary.OurSide(rawValue: side) != nil
            ourSide = side.isEmpty ? "" : known ? side : "other"
            ourSideText = !side.isEmpty && !known ? side : ""
            oppositeParty = p.oppositeParty ?? ""
            color = MatterVocabulary.ProjectColor.normalize(p.color)?.rawValue
            banner = p.banner == "image" ? "image" : MatterMeta.bannerPreset(banner: p.banner, color: p.color).rawValue
            linkedCaseID = (p.linkedCaseID?.isEmpty == false) ? p.linkedCaseID : nil
            courtStatus = p.courtStatus == "not_filed" ? "not_filed" : ""
        }

        /// The side as it is stored: the key, or the user's own words for Other.
        var ourSideValue: String {
            ourSide == "other" ? (JSCompat.trim(ourSideText).isEmpty ? "other" : JSCompat.trim(ourSideText)) : ourSide
        }

        /// `fieldsFromDraft`: **every** field the form shows, on every save — an absent key keeps
        /// its stored value, so a form that sent only what changed could never clear anything.
        func body(banner: String) -> ProjectBody {
            let t = JSCompat.trim
            var f: [String: JSONValue] = [
                "name": .string(t(name)), "client": .string(t(client)), "description": .string(t(description)),
                "forumType": .string(forumType), "forumName": .string(t(forumName)), "caseType": .string(t(caseType)),
                "caseNumber": .string(t(caseNumber)), "caseYear": .string(t(caseYear)), "cnr": .string(t(cnr)),
                "stage": .string(t(stage)), "status": .string(status), "priority": .string(priority),
                "nextHearingDate": .string(nextHearingDate), "filingDate": .string(filingDate),
                "practiceArea": .string(practiceArea), "ourSide": .string(ourSideValue),
                "oppositeParty": .string(t(oppositeParty)),
                "color": MatterVocabulary.ProjectColor.normalize(color).map { .string($0.rawValue) } ?? .null,
                "banner": .string(banner),
                // Sent every time: null clears a "not filed yet" the user has taken back.
                "courtStatus": courtStatus == "not_filed" ? .string("not_filed") : .null,
            ]
            // Carried back unchanged, never edited here: linking is `/project-link-case`'s.
            if let linkedCaseID { f["linkedCaseId"] = .string(linkedCaseID) }
            return ProjectBody(id: id, fields: f)
        }
    }

    /// The banner a new matter starts with: the preset the user's matters use least, the first
    /// of them on a tie — so a fresh list is not eight navy cards in a row.
    static func leastUsedBanner(_ projects: [Project]) -> MatterVocabulary.BannerPreset {
        var used: [MatterVocabulary.BannerPreset: Int] = [:]
        for p in projects {
            if let preset = p.banner.flatMap(MatterVocabulary.BannerPreset.init(rawValue:)) { used[preset, default: 0] += 1 }
        }
        let all = MatterVocabulary.BannerPreset.allCases
        return all.reduce(all[0]) { best, b in (used[b] ?? 0) < (used[best] ?? 0) ? b : best }
    }

    // MARK: - Tasks

    struct TaskForm: Equatable, Sendable {
        var id: String?
        var title = ""
        var notes = ""
        var dueDate = ""
        var kind = "task"
        var priority = "normal"
        var status = "open"

        /// `blankTask`: a limitation entry starts at high priority.
        init(kind: String = "task") {
            self.kind = kind
            priority = kind == "limitation" ? "high" : "normal"
        }

        /// `draftOf`.
        init(_ t: ProjectTask) {
            id = t.id
            title = t.title ?? ""
            notes = t.notes ?? ""
            dueDate = MatterRecord.dayKey(t.dueDateRaw)
            kind = t.kind.flatMap(MatterVocabulary.TaskKind.init(rawValue:))?.rawValue ?? "task"
            priority = (t.priority?.isEmpty == false) ? t.priority! : "normal"
            status = t.status == "done" ? "done" : "open"
        }

        /// `bodyOf`: the whole task on every save, the done toggle included.
        func body(projectID: String) -> [String: JSONValue] {
            var b: [String: JSONValue] = [
                "projectId": .string(projectID), "title": .string(JSCompat.trim(title)),
                "notes": .string(JSCompat.trim(notes)), "dueDate": .string(dueDate), "kind": .string(kind),
                "priority": .string(priority), "status": .string(status),
            ]
            if let id, !id.isEmpty { b["id"] = .string(id) }
            return b
        }

        /// The task with its tick flipped.
        var toggled: TaskForm {
            var t = self
            t.status = status == "done" ? "open" : "done"
            return t
        }
    }

    // MARK: - Fees, payments, expenses

    struct LedgerForm: Equatable, Sendable {
        var id: String?
        var kind = "fee"
        var title = ""
        var amountText = ""
        var entryDate = ""
        var mode = "upi"
        var reference = ""
        var category = "court_fee"
        var receiptFile = ""
        var notes = ""

        /// `blankEntry`: dated today (India), paid by UPI, a court fee.
        init(kind: String, today: String) {
            self.kind = kind
            entryDate = today
        }

        /// `draftOf`.
        init(_ e: LedgerEntry, today: String) {
            id = e.id
            kind = e.kind ?? "fee"
            title = e.title ?? ""
            amountText = Self.amountText(paise: e.paise)
            let day = MatterRecord.dayKey(e.entryDateRaw)
            entryDate = day.isEmpty ? today : day
            mode = (e.mode?.isEmpty == false) ? e.mode! : "upi"
            reference = e.reference ?? ""
            category = (e.category?.isEmpty == false) ? e.category! : "other"
            receiptFile = e.receiptFile ?? ""
            notes = e.notes ?? ""
        }

        /// `amountText`: "25000", "25000.50" — rupees as typed back into the box, never a float tail.
        static func amountText(paise: Int) -> String {
            guard paise > 0 else { return "" }
            let rest = paise % 100
            return "\(paise / 100)\(rest == 0 ? "" : ".\(rest < 10 ? "0" : "")\(rest)")"
        }

        /// The reference field's label and hint: by payment mode, or the expense's challan.
        var referenceField: Ledger.ReferenceField? {
            switch kind {
            case "payment": return Ledger.referenceField(mode: mode) ?? Ledger.referenceField(mode: "other")
            case "expense": return Ledger.expenseReference
            default: return nil
            }
        }

        /// The body, with fields that do not belong to the kind sent empty — an entry switched from
        /// a payment to a fee must not keep a stale mode or slip.
        func body(projectID: String, rupees: Double) -> [String: JSONValue] {
            var b: [String: JSONValue] = [
                "projectId": .string(projectID), "kind": .string(kind), "title": .string(JSCompat.trim(title)),
                "amount": .number(rupees), "entryDate": .string(entryDate),
                "mode": kind == "payment" ? .string(mode) : .null,
                "reference": .string(kind == "fee" ? "" : JSCompat.trim(reference)),
                "category": kind == "expense" ? .string(category) : .null,
                "receiptFile": .string(kind == "fee" ? "" : receiptFile),
                "notes": .string(JSCompat.trim(notes)),
            ]
            if let id, !id.isEmpty { b["id"] = .string(id) }
            return b
        }
    }

    // MARK: - People

    struct PersonForm: Equatable, Sendable {
        var id: String?
        var role = "client"
        var name = ""
        var phone = ""
        var email = ""
        var address = ""
        var notes = ""

        init(role: String = "client", name: String = "") {
            self.role = role
            self.name = name
        }

        init(_ p: ProjectPerson) {
            id = p.id
            role = p.role.flatMap(MatterVocabulary.PeopleRole.init(rawValue:))?.rawValue ?? "other"
            name = p.name ?? ""
            phone = p.phone ?? ""
            email = p.email ?? ""
            address = p.address ?? ""
            notes = p.notes ?? ""
        }

        func body(projectID: String) -> [String: JSONValue] {
            var b: [String: JSONValue] = [
                "projectId": .string(projectID), "role": .string(role), "name": .string(JSCompat.trim(name)),
                "phone": .string(JSCompat.trim(phone)), "email": .string(JSCompat.trim(email)),
                "address": .string(JSCompat.trim(address)), "notes": .string(JSCompat.trim(notes)),
            ]
            if let id, !id.isEmpty { b["id"] = .string(id) }
            return b
        }
    }

    // MARK: - Chronology

    struct EntryForm: Equatable, Sendable {
        /// How much of the date is known: a day, a month, or only the year.
        enum Precision: String, CaseIterable, Sendable {
            case day, month, year
            var label: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
        }

        var id: String?
        var kind = "event"
        /// `YYYY-MM-DD`; cut to the precision when sent.
        var day = ""
        var precision = Precision.day
        var title = ""
        var body = ""
        /// An edited entry keeps where it came from: an AI-found event the user corrected still
        /// came from that document.
        var source = "manual"
        var sourceRef = ""

        init(today: String) { day = today }

        /// An own entry of the chronology, to edit.
        init(_ e: MatterRecord.Entry, today: String) {
            id = e.id
            kind = MatterVocabulary.ChronoKind(rawValue: e.kind) != nil ? e.kind : "note"
            title = e.title
            body = e.body
            source = e.src.rawValue
            sourceRef = e.sourceRef
            let raw = e.day
            switch raw.count {
            case 4: day = "\(raw)-01-01"; precision = .year
            case 7: day = "\(raw)-01"; precision = .month
            default: day = raw.isEmpty ? today : raw; precision = .day
            }
        }

        /// The date as sent: `YYYY`, `YYYY-MM` or `YYYY-MM-DD`.
        var eventDate: String {
            switch precision {
            case .year: return String(day.prefix(4))
            case .month: return String(day.prefix(7))
            case .day: return day
            }
        }

        func body(projectID: String) -> [String: JSONValue] {
            var b: [String: JSONValue] = [
                "projectId": .string(projectID), "kind": .string(kind), "title": .string(JSCompat.trim(title)),
                "body": .string(JSCompat.trim(body)), "eventDate": .string(eventDate),
                "source": .string(source.isEmpty ? "manual" : source),
            ]
            if let id, !id.isEmpty { b["id"] = .string(id) }
            if !sourceRef.isEmpty { b["sourceRef"] = .string(sourceRef) }
            return b
        }
    }
}

typealias MatterDraft = MatterDrafts.MatterForm
typealias TaskDraft = MatterDrafts.TaskForm
typealias LedgerDraft = MatterDrafts.LedgerForm
typealias PersonDraft = MatterDrafts.PersonForm
typealias ChronologyDraft = MatterDrafts.EntryForm
