import XCTest
@testable import EmperorCore

/// Holds the matter rules and money port to answers produced by running the platform's own
/// modules (`scripts/generate-matter-fixtures.mjs` → `MatterGolden.swift`). Every case is
/// dispatched on its `fn`; a function the dispatch does not know fails the test rather than being
/// skipped. When this fails after a platform change, regenerate the fixture — never edit it.
final class MatterGoldenTests: XCTestCase {

    private struct Case: Decodable {
        let fn: String
        let input: JSONValue
        let expected: JSONValue
    }

    private struct Fixture: Decodable {
        let cases: [Case]
    }

    private static let fixture: Fixture = {
        do {
            return try JSONDecoder().decode(Fixture.self, from: Data(MatterGolden.json.utf8))
        } catch {
            fatalError("MatterGolden.json does not decode: \(error)")
        }
    }()

    func testTheFixtureCoversEveryPortedFunction() {
        let fns = Set(Self.fixture.cases.map(\.fn))
        XCTAssertGreaterThan(Self.fixture.cases.count, 400)
        for fn in ["tidyCourtName", "parseRupees", "amountInWordsINR.number", "computeNextHearing", "chronologyEntries",
                   "nextHearing", "bannerForCase", "findTrackedCase", "buildReceiptHtml", "listOfDatesHtml",
                   "practiceAreaFromCase", "matterNameFromCase", "groupTasks", "projectFileList", "localeCompare"] {
            XCTAssertTrue(fns.contains(fn), fn)
        }
        XCTAssertGreaterThanOrEqual(Self.fixture.cases.filter { $0.fn == "practiceAreaFromCase" }.count, 40)
        XCTAssertGreaterThanOrEqual(Self.fixture.cases.filter { $0.fn == "matterNameFromCase" }.count, 20)
        XCTAssertGreaterThanOrEqual(Self.fixture.cases.filter { $0.fn == "computeNextHearing" }.count, 30)
        XCTAssertGreaterThanOrEqual(Self.fixture.cases.filter { $0.fn == "chronologyEntries" }.count, 25)
        XCTAssertGreaterThanOrEqual(Self.fixture.cases.filter { $0.fn == "nextHearing" }.count, 10)
        XCTAssertGreaterThanOrEqual(Self.fixture.cases.filter { $0.fn == "bannerForCase" }.count, 12)
        XCTAssertGreaterThanOrEqual(Self.fixture.cases.filter { $0.fn == "findTrackedCase" }.count, 10)
        XCTAssertGreaterThanOrEqual(Self.fixture.cases.filter { $0.fn == "buildReceiptHtml" }.count, 6)
        XCTAssertGreaterThanOrEqual(Self.fixture.cases.filter { $0.fn == "listOfDatesHtml" }.count, 4)
        XCTAssertGreaterThanOrEqual(Self.fixture.cases.filter {
            $0.fn == "parseRupees" && $0.expected["ok"] == .bool(false)
        }.count, 15)
    }

    func testEveryCaseMatchesThePlatform() {
        var failures: [String] = []
        for c in Self.fixture.cases {
            guard let actual = MatterGoldenDispatch.run(c.fn, c.input) else {
                failures.append("no dispatch for \(c.fn)")
                continue
            }
            if !MatterGoldenDispatch.same(c.fn, actual, c.expected) {
                failures.append("\(c.fn) \(MatterGoldenDispatch.text(c.input).prefix(300))\n   got      \(MatterGoldenDispatch.text(actual).prefix(600))\n   expected \(MatterGoldenDispatch.text(c.expected).prefix(600))")
            }
        }
        XCTAssertTrue(failures.isEmpty, "\(failures.count) of \(Self.fixture.cases.count) cases differ:\n"
                      + failures.prefix(40).joined(separator: "\n"))
    }
}

// MARK: - Dispatch

/// One fixture case → the Swift port's answer, as JSON in the fixture's shape. Nil only for a
/// function this does not know, which the test reports.
enum MatterGoldenDispatch {

    // MARK: Reading inputs

    static func str(_ v: JSONValue?) -> String? {
        switch v {
        case .string(let s)?: return s
        case .number(let n)?: return JSCompat.numberString(n)
        default: return nil
        }
    }

    static func num(_ v: JSONValue?) -> Double? {
        switch v {
        case .number(let n)?: return n
        case .object(let o)?:
            switch o["special"]?.stringValue {
            case "NaN": return .nan
            case "Infinity": return .infinity
            case "-Infinity": return -.infinity
            default: return nil
            }
        default: return nil
        }
    }

    static func int(_ v: JSONValue?) -> Int? { num(v).map { Int($0) } }
    static func bool(_ v: JSONValue?) -> Bool { v?.boolValue ?? false }
    static func array(_ v: JSONValue?) -> [JSONValue] {
        if case .array(let a)? = v { return a }
        return []
    }
    static func object(_ v: JSONValue?) -> [String: JSONValue] {
        if case .object(let o)? = v { return o }
        return [:]
    }

    // MARK: Writing answers

    static func j(_ s: String?) -> JSONValue { s.map(JSONValue.string) ?? .null }
    static func j(_ n: Int?) -> JSONValue { n.map { .number(Double($0)) } ?? .null }
    static func j(_ d: Double) -> JSONValue { .number(d) }
    static func j(_ b: Bool) -> JSONValue { .bool(b) }
    static func j(_ list: [String]) -> JSONValue { .array(list.map(JSONValue.string)) }
    static func pairs(_ list: [(String, String)]) -> JSONValue { .array(list.map { .array([.string($0.0), .string($0.1)]) }) }

    static func attempt(_ body: () throws -> String?) -> JSONValue {
        do { return .object(["ok": j(try body())]) } catch let e as MatterRuleError {
            return .object(["error": .string(e.message)])
        } catch { return .object(["error": .string("\(error)")]) }
    }

    static func totals(_ t: MatterRules.LedgerTotals) -> JSONValue {
        .object(["billed": j(t.billed), "received": j(t.received), "outstanding": j(t.outstanding), "expenses": j(t.expenses)])
    }

    /// Equal answers. Two shapes are compared loosely, each for a stated reason: a server
    /// allowlist (`serverVocab`) as a set, since the order is the client's to choose; and the
    /// `/save-case` body (`casePayload`) without its nulls, which the app's request leaves out.
    static func same(_ fn: String, _ a: JSONValue, _ b: JSONValue) -> Bool {
        switch fn {
        case "serverVocab":
            return Set(array(a).compactMap { str($0) }) == Set(array(b).compactMap { str($0) })
                && array(a).count == array(b).count
        case "casePayload":
            return object(a).filter { $0.value != .null } == object(b).filter { $0.value != .null }
        default:
            return a == b
        }
    }

    static func text(_ v: JSONValue) -> String {
        guard let data = try? JSONEncoder().encode(v) else { return "\(v)" }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: Models from fixture JSON

    static func entry(_ v: JSONValue?) -> Ledger.Entry {
        let o = object(v)
        var paise: Int?
        switch o["amount_paise"] {
        case .number(let n)?: paise = n == n.rounded() ? Int(n) : nil
        case .string(let s)?: paise = !s.isEmpty && s.allSatisfy(\.isASCII) && s.allSatisfy(\.isNumber) ? Int(s) : nil
        default: paise = nil
        }
        var amount: Double?
        switch o["amount"] {
        case .number(let n)?: amount = n
        case .string(let s)?: amount = Double(s) ?? .nan
        default: amount = nil
        }
        return Ledger.Entry(id: str(o["id"]) ?? "", kind: str(o["kind"]) ?? "", title: str(o["title"]), amountPaise: paise,
                            amount: amount, entryDate: str(o["entry_date"]), createdAt: str(o["created_at"]),
                            mode: str(o["mode"]), reference: str(o["reference"]), category: str(o["category"]))
    }

    static func taskKey(_ v: JSONValue?) -> MatterDates.TaskSortKey {
        let o = object(v)
        return MatterDates.TaskSortKey(status: str(o["status"]), kind: str(o["kind"]), dueDate: str(o["due_date"]),
                                       priority: str(o["priority"]), createdAt: str(o["created_at"]),
                                       completedAt: str(o["completed_at"]), updatedAt: str(o["updated_at"]))
    }

    static func update(_ v: JSONValue) -> MatterRecord.Update {
        let o = object(v)
        return MatterRecord.Update(id: str(o["id"]) ?? "", kind: str(o["kind"]), title: str(o["title"]), body: str(o["body"]),
                                   eventDate: str(o["event_date"]), createdAt: str(o["created_at"]),
                                   source: str(o["source"]), sourceRef: str(o["source_ref"]))
    }

    static func courtItem(_ v: JSONValue) -> MatterRecord.CourtItem {
        let o = object(v)
        return MatterRecord.CourtItem(id: str(o["id"]) ?? "", section: str(o["section"]) ?? "", title: str(o["title"]),
                                      subtitle: str(o["subtitle"]), itemDate: str(o["item_date"]),
                                      data: MatterRecord.CourtItem.data(fromWire: o["data"]))
    }

    static func chronology(_ input: JSONValue) -> [MatterRecord.Entry] {
        MatterRecord.chronology(updates: array(input["updates"]).map(update), court: array(input["court"]).map(courtItem))
    }

    static func pick(_ v: JSONValue?) -> MatterMeta.CasePick {
        let o = object(v)
        return MatterMeta.CasePick(courtType: str(o["courtType"]), courtCode: str(o["courtCode"]), courtName: str(o["courtName"]),
                                   caseType: str(o["caseType"]), caseNumber: str(o["caseNumber"]), caseYear: str(o["caseYear"]),
                                   cnr: str(o["cnr"]), diaryNumber: str(o["diaryNumber"]), title: str(o["title"]),
                                   parties: str(o["parties"]), judge: str(o["judge"]), status: str(o["status"]),
                                   stage: str(o["stage"]), nextHearingDate: str(o["nextHearingDate"]), scrapeRef: str(o["scrapeRef"]))
    }

    static func identity(project v: JSONValue?) -> MatterRules.MatterIdentity {
        let o = object(v)
        return MatterRules.MatterIdentity(forumType: str(o["forum_type"]), forumName: str(o["forum_name"]),
                                          caseType: str(o["case_type"]), caseNumber: str(o["case_number"]),
                                          caseYear: str(o["case_year"]), cnr: str(o["cnr"]),
                                          nextHearingDate: str(o["next_hearing_date"]))
    }

    static func identity(kase v: JSONValue?) -> MatterRules.CaseIdentity {
        let o = object(v)
        return MatterRules.CaseIdentity(courtType: str(o["court_type"]), courtName: str(o["court_name"]),
                                        caseType: str(o["case_type"]), caseNumber: str(o["case_number"]),
                                        caseYear: str(o["case_year"]), cnr: str(o["cnr"]), diaryNumber: str(o["diary_number"]),
                                        nextHearingDate: str(o["next_hearing_date"]))
    }

    static func vocab<V: MatterVocab>(_ type: V.Type) -> JSONValue { pairs(V.allCases.map { ($0.rawValue, $0.label) }) }
    static func raw<V: MatterVocab>(_ type: V.Type) -> [String] { V.allCases.map(\.rawValue) }

    static func hex(_ value: UInt32) -> String {
        let digits = String(value, radix: 16, uppercase: true)
        return "#" + String(repeating: "0", count: max(0, 6 - digits.count)) + digits
    }

    // MARK: The dispatch

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    static func run(_ fn: String, _ input: JSONValue) -> JSONValue? {
        let i = input
        switch fn {
        case "vocab":
            switch str(i["name"]) {
            case "practiceAreas": return vocab(MatterVocabulary.PracticeArea.self)
            case "ourSides": return vocab(MatterVocabulary.OurSide.self)
            case "banners": return vocab(MatterVocabulary.BannerPreset.self)
            case "taskKinds": return vocab(MatterVocabulary.TaskKind.self)
            case "expenseCategories": return vocab(MatterVocabulary.ExpenseCategory.self)
            case "paymentModes": return vocab(MatterVocabulary.PaymentMode.self)
            case "peopleRoles": return vocab(MatterVocabulary.PeopleRole.self)
            case "sections": return vocab(MatterVocabulary.MatterSection.self)
            case "ledgerKinds": return vocab(MatterVocabulary.LedgerKind.self)
            case "chronoKinds": return vocab(MatterVocabulary.ChronoKind.self)
            case "sources":
                // A map on the web (`SOURCE_LABEL`), so its key order carries no meaning.
                return pairs(MatterVocabulary.UpdateSource.allCases.map { ($0.rawValue, $0.label) }
                    .sorted { ["manual", "court", "ai"].firstIndex(of: $0.0)! < ["manual", "court", "ai"].firstIndex(of: $1.0)! })
            case "projectColors": return vocab(MatterVocabulary.ProjectColor.self)
            case "forums": return vocab(MatterVocabulary.Forum.self)
            case "statuses": return vocab(MatterVocabulary.ProjectStatus.self)
            case "priorities": return vocab(MatterVocabulary.Priority.self)
            case "taskGroups": return pairs(MatterDates.TaskGroup.allCases.map { ($0.rawValue, $0.title) })
            default: return nil
            }
        case "serverVocab":
            // Compared as sets (see `same`): the form shows priorities high-first, payment modes UPI-first.
            let list: [String]
            switch str(i["name"]) {
            case "courtStatuses": list = MatterVocabulary.courtStatuses
            case "practiceAreas": list = raw(MatterVocabulary.PracticeArea.self)
            case "ourSides": list = raw(MatterVocabulary.OurSide.self)
            case "banners": list = raw(MatterVocabulary.BannerPreset.self)
            case "projectStatuses": list = raw(MatterVocabulary.ProjectStatus.self)
            case "priorities": list = raw(MatterVocabulary.Priority.self)
            case "updateKinds": list = raw(MatterVocabulary.UpdateKind.self)
            case "updateSources": list = raw(MatterVocabulary.UpdateSource.self)
            case "taskKinds": list = raw(MatterVocabulary.TaskKind.self)
            case "taskStatuses": list = raw(MatterVocabulary.TaskStatus.self)
            case "ledgerKinds": list = raw(MatterVocabulary.LedgerKind.self)
            case "paymentModes": list = raw(MatterVocabulary.PaymentMode.self)
            case "expenseCategories": list = raw(MatterVocabulary.ExpenseCategory.self)
            case "peopleRoles": list = raw(MatterVocabulary.PeopleRole.self)
            case "criticalKinds": list = MatterDates.criticalKinds
            default: return nil
            }
            return j(list)
        case "constants":
            var refs: [String: JSONValue] = [:]
            for mode in ["upi", "bank", "cheque", "cash", "card", "other"] {
                let r = Ledger.referenceField(mode: mode)!
                refs[mode] = .object(["label": j(r.label), "placeholder": j(r.placeholder)])
            }
            return .object([
                "clientMaxRupees": j(INR.maxRupees), "serverMaxRupees": j(INR.serverMaxRupees), "soonDays": j(MatterDates.soonDays),
                "bannerMaxBytes": j(MatterRules.bannerMaxBytes),
                "bannerExts": .object(MatterRules.bannerExtensions.mapValues(JSONValue.string)),
                "bannerMimeByExt": .object(MatterRules.bannerMIMEByExtension.mapValues(JSONValue.string)),
                "caseRefreshGapMs": j(MatterRules.caseRefreshGapMillis), "trackedPrefix": j(MatterMeta.trackedPrefix),
                "fieldLimits": .object(MatterRules.fieldLimits.mapValues { j($0) }),
                "referenceField": .object(refs),
                "expenseReference": .object(["label": j(Ledger.expenseReference.label),
                                             "placeholder": j(Ledger.expenseReference.placeholder)]),
                "categoryLabels": .object(MatterMeta.courtCategoryLabels.mapValues(JSONValue.string)),
            ])
        case "banner":
            var presets: [String: JSONValue] = [:]
            for (k, v) in MatterBanner.presets { presets[k.rawValue] = j([hex(v.from), hex(v.to)]) }
            var dots: [String: JSONValue] = [:]
            for (k, v) in MatterBanner.statusDot { dots[k.rawValue] = j(hex(v)) }
            let p = MatterBanner.plate
            return .object([
                "presets": .object(presets), "fromPercent": j((MatterBanner.fromShare * 100).rounded()),
                "toPercent": j((MatterBanner.toShare * 100).rounded()),
                "plate": .array([j((p.red * 255).rounded()), j((p.green * 255).rounded()), j((p.blue * 255).rounded()), j(p.opacity)]),
                "statusDot": .object(dots),
            ])
        case "localeCompare":
            return j(JSCompat.localeCompare(str(i["a"]) ?? "", str(i["b"]) ?? ""))

        // Court names and money
        case "tidyCourtName": return j(CourtNames.tidy(str(i["raw"]), title: bool(i["title"])))
        case "toPaise.number": return j(INR.toPaise(number: num(i["amount"])!))
        case "toPaise.text": return j(INR.toPaise(text: str(i["amount"])))
        case "amountInWordsINR.number": return j(INR.words(paise: INR.toPaise(number: num(i["amount"])!)))
        case "amountInWordsINR.text": return j(INR.words(paise: INR.toPaise(text: str(i["amount"]))))
        case "parseRupees":
            switch INR.parse(str(i["text"])) {
            case .success(let p): return .object(["ok": .bool(true), "paise": j(p.paise), "rupees": j(p.rupees)])
            case .failure(let e): return .object(["ok": .bool(false), "error": j(e.message)])
            }
        case "rupeesFigure.number": return j(INR.figure(paise: INR.toPaise(number: num(i["amount"])!)))
        case "financialYear": return j(INR.financialYear(str(i["day"])))
        case "receiptNumber":
            return j(INR.receiptNumber(id: str(i["id"]), entryDate: str(i["entry_date"]), createdAt: str(i["created_at"])))
        case "inr": return j(INR.display(rupees: num(i["rupees"])!))
        case "rupees": return j(Ledger.rupees(num(i["rupees"])!))
        case "paiseOf": return j(Ledger.paise(of: entry(i["entry"])))
        case "sortEntries": return j(Ledger.sorted(array(i["entries"]).map { entry($0) }).map(\.id))
        case "ledger.ledgerTotals": return totals(Ledger.totals(array(i["entries"]).map { entry($0) }))
        case "expenseCategories":
            return .array(Ledger.expenseCategories(array(i["entries"]).map { entry($0) }).map {
                .object(["key": j($0.key), "label": j($0.label), "paise": j($0.paise), "count": j($0.count)])
            })
        case "modeLabel": return j(Ledger.modeLabel(str(i["mode"])))
        case "categoryLabel": return j(Ledger.categoryLabel(str(i["category"])))
        case "projectFileList":
            let listing = i["listing"]
            let nodes = array(listing?["folders"]) + array(listing?["files"])
            guard let data = try? JSONEncoder().encode(nodes),
                  let items = try? JSONDecoder().decode([FileNode].self, from: data) else { return .string("undecodable listing") }
            return .array(Ledger.projectFileList(root: str(listing?["root"]), items: items).map {
                .object(["name": j($0.name), "path": j($0.path), "folder": j($0.folder)])
            })
        case "receiptFileName": return j(Ledger.receiptFileName(str(i["path"])))

        // Dates
        case "dayKeyOf": return j(MatterDates.dayKeyOf(str(i["value"])))
        case "dates.fmtDay": return j(MatterDates.fmtDay(str(i["value"])))
        case "daysBetween": return j(MatterDates.daysBetween(str(i["from"]), str(i["to"])))
        case "addDays": return j(MatterDates.addDays(str(i["from"]), int(i["n"])!))
        case "taskBucket":
            let t = taskKey(i["task"])
            return j(MatterDates.taskBucket(status: t.status, dueDate: t.dueDate, today: str(i["today"])!).rawValue)
        case "dueInfo":
            guard let d = MatterDates.dueInfo(str(i["dueDate"]), today: str(i["today"])!, done: bool(i["done"])) else { return .null }
            return .object(["text": j(d.text), "rel": j(d.rel), "tone": j(d.tone.rawValue), "days": j(d.days)])
        case "groupTasks":
            let tasks = array(i["tasks"])
            let groups = MatterDates.group(tasks, key: { taskKey($0) }, today: str(i["today"])!)
            var out: [String: JSONValue] = [:]
            for (g, list) in groups { out[g.rawValue] = j(list.map { str($0["id"]) ?? "" }) }
            return .object(out)
        case "compareTasks": return j(MatterDates.compareOrder(taskKey(i["a"]), taskKey(i["b"])))

        // Receipt
        case "receipt.caseNumberOf":
            let p = i["project"]
            return j(MatterReceipt.caseNumber(caseNumber: str(p?["case_number"]), caseType: str(p?["case_type"]),
                                              caseYear: str(p?["case_year"])))
        case "receiptClient":
            let people = array(i["people"]).map {
                MatterReceipt.Person(role: str($0["role"]), name: str($0["name"]), address: str($0["address"]))
            }
            let c = MatterReceipt.client(projectClient: str(i["project"]?["client"]), people: people)
            return .object(["name": j(c.name), "address": j(c.address)])
        case "advocateFromProfile":
            let u = i["user"]
            let a = MatterReceipt.advocate(name: str(u?["name"]), title: str(u?["title"]), organization: str(u?["organization"]),
                                           phone: str(u?["phone"]), email: str(u?["email"]))
            return .object(["name": j(a.name), "designation": j(a.designation), "chambers": j(a.chambers),
                            "phone": j(a.phone), "email": j(a.email)])
        case "matterFromProject":
            let p = i["project"]
            let m = MatterReceipt.matter(name: str(p?["name"]), caseNumber: str(p?["case_number"]), caseType: str(p?["case_type"]),
                                         caseYear: str(p?["case_year"]), forumName: str(p?["forum_name"]))
            return .object(["title": j(m.title), "caseNo": j(m.caseNo), "forum": j(m.forum)])
        case "buildReceiptHtml":
            let a = object(i["advocate"]), c = object(i["client"]), m = object(i["matter"])
            return j(MatterReceipt.html(
                advocate: MatterReceipt.Advocate(name: str(a["name"]) ?? "", designation: str(a["designation"]) ?? "",
                                                 chambers: str(a["chambers"]) ?? "", phone: str(a["phone"]) ?? "",
                                                 email: str(a["email"]) ?? ""),
                client: MatterReceipt.Client(name: str(c["name"]) ?? "", address: str(c["address"]) ?? ""),
                matter: MatterReceipt.Matter(title: str(m["title"]) ?? "", caseNo: str(m["caseNo"]) ?? "", forum: str(m["forum"]) ?? ""),
                entry: entry(i["entry"])))

        // rules.js
        case "optText":
            return attempt { try MatterRules.optText(str(i["value"]), label: str(i["label"])!, max: int(i["max"])!) }
        case "reqText":
            return attempt { try MatterRules.reqText(str(i["value"]), label: str(i["label"])!, max: int(i["max"])!) }
        case "oneOf":
            return attempt {
                try MatterRules.oneOf(str(i["value"]), allowed: array(i["allowed"]).compactMap { str($0) },
                                      label: str(i["label"])!, fallback: str(i["fallback"]))
            }
        case "istDay": return j(MatterRules.istDay(epochMillis: num(i["at"])!))
        case "istDateOf": return j(MatterRules.istDateOf(str(i["value"])))
        case "dayOf": return attempt { try MatterRules.dayOf(str(i["value"]), label: str(i["label"])!) }
        case "eventDateOf": return attempt { try MatterRules.eventDateOf(str(i["value"]), label: str(i["label"])!) }
        case "isTodayOrLaterIst": return j(MatterRules.isTodayOrLaterIst(str(i["value"]), today: str(i["today"])!))
        case "computeNextHearing":
            return j(MatterRules.computeNextHearing(stored: str(i["stored"]), removed: str(i["removed"]),
                                                    hearings: array(i["hearings"]).map { str($0) },
                                                    caseNext: str(i["caseNext"]), today: str(i["today"])!))
        case "rupeesToPaise.number":
            return attempt { String(try MatterRules.rupeesToPaise(.number(num(i["amount"])!))) }.paiseAnswer
        case "rupeesToPaise.text":
            let label = str(i["label"]) ?? "amount"
            return attempt { String(try MatterRules.rupeesToPaise(.text(str(i["amount"])!), label: label)) }.paiseAnswer
        case "paiseToRupees": return j(MatterRules.paiseToRupees(int(i["paise"])!))
        case "rules.ledgerTotals":
            return totals(MatterRules.ledgerTotals(array(i["rows"]).map { (kind: str($0["kind"]) ?? "", paise: int($0["amount_paise"]) ?? 0) }))
        case "bannerOf": return j(MatterRules.bannerOf(str(i["value"])))
        case "ourSideOf": return attempt { try MatterRules.ourSideOf(str(i["value"])) }
        case "confirmMatches": return j(MatterRules.confirmMatches(name: str(i["name"]), confirm: str(i["confirm"])))
        case "fieldsFromCase":
            return .object(MatterRules.fieldsFromCase(project: identity(project: i["project"]), kase: identity(kase: i["kase"]))
                .mapValues(JSONValue.string))
        case "fieldsClearedOnUnlink":
            return .object(MatterRules.fieldsClearedOnUnlink(project: identity(project: i["project"]), kase: identity(kase: i["kase"]))
                .mapValues { j($0) })
        case "practiceAreaFromCase":
            return j(MatterRules.practiceAreaFromCase(caseType: str(i["case_type"]), courtType: str(i["court_type"])))
        case "matterNameFromCase":
            let k = i["kase"]
            return j(MatterRules.matterNameFromCase(title: str(k?["title"]), caseType: str(k?["case_type"]),
                                                    caseNumber: str(k?["case_number"]), caseYear: str(k?["case_year"])))
        case "receiptPathOf":
            return attempt { try MatterRules.receiptPathOf(str(i["value"]), projectID: str(i["projectId"])!) }
        case "validEmail": return j(MatterRules.validEmail(str(i["value"])))
        case "validPhone": return j(MatterRules.validPhone(str(i["value"])))
        case "refreshWaitSeconds":
            return j(MatterRules.refreshWaitSeconds(lastAtMillis: num(i["lastAt"]), nowMillis: num(i["now"])!))

        // projectRecord.js
        case "record.dayKey": return j(MatterRecord.dayKey(str(i["value"])))
        case "record.fmtDay": return j(MatterRecord.fmtDay(str(i["value"])))
        case "fmtDots": return j(MatterRecord.fmtDots(str(i["value"])))
        case "weekdayOf": return j(MatterRecord.weekdayOf(str(i["value"])))
        case "daysFromToday": return j(MatterRecord.daysFromToday(str(i["value"]), today: str(i["today"])!))
        case "relDays": return j(MatterRecord.relDays(int(i["n"])))
        case "parseDocDate": return j(MatterRecord.parseDocDate(str(i["value"])))
        case "orderTitle": return j(MatterRecord.orderTitle(str(i["raw"])))
        case "plainCourtText": return j(MatterRecord.plainCourtText(str(i["raw"])))
        case "hearingFacts":
            let h = MatterRecord.hearingFacts(courtItem(i["item"] ?? .null))
            return .object(["purpose": j(h.purpose), "where": j(h.where), "coram": j(h.coram), "remarks": j(h.remarks),
                            "supplementary": j(h.supplementary), "nextDate": j(h.nextDate)])
        case "ordersOf": return j(MatterRecord.orders(array(i["court"]).map(courtItem)).map(\.id))
        case "chronologyEntries":
            return .array(chronology(i).map { e in
                .object(["key": j(e.key), "id": j(e.id), "src": j(e.src.rawValue), "own": j(e.own), "kind": j(e.kind),
                         "day": j(e.day), "title": j(e.title), "body": j(e.body), "sourceRef": j(e.sourceRef),
                         "created": j(e.created)])
            })
        case "sortChronology":
            return j(MatterRecord.sorted(chronology(i), newestFirst: bool(i["newestFirst"])).map(\.key))
        case "eventText": return j(chronology(i).map(MatterRecord.eventText))
        case "nextHearing":
            let r = MatterRecord.nextHearing(projectNext: str(i["project"]?["next_hearing_date"]),
                                             caseNext: str(i["linkedCase"]?["next_hearing_date"]),
                                             court: array(i["court"]).map(courtItem), today: str(i["today"])!)
            guard let r else { return .null }
            return .object(["day": j(r.day), "from": j(r.from.rawValue), "days": j(r.days),
                            "listing": j(r.listing?.id), "latest": j(r.latest?.id)])
        case "record.ourSideLabel": return j(MatterRecord.sideLabelForTitle(str(i["side"])))
        case "meta.ourSideLabel": return j(MatterMeta.sideLabel(str(i["side"])))
        case "caseNoLabel":
            let p = i["project"]
            return j(MatterRecord.caseNoLabel(number: str(p?["case_number"]), type: str(p?["case_type"]), year: str(p?["case_year"])))
        case "cnrLabel": return j(MatterRecord.cnrLabel(str(i["value"])))
        case "listOfDatesHtml":
            let p = object(i["project"])
            let project = MatterRecord.ListOfDatesInput(
                name: str(p["name"]), forumName: str(p["forum_name"]), caseType: str(p["case_type"]),
                caseNumber: str(p["case_number"]), caseYear: str(p["case_year"]), client: str(p["client"]),
                oppositeParty: str(p["opposite_party"]), ourSide: str(p["our_side"]))
            var linked: MatterRecord.LinkedCaseInput?
            if case .object(let l)? = i["linkedCase"] {
                linked = MatterRecord.LinkedCaseInput(courtName: str(l["court_name"]), caseType: str(l["case_type"]),
                                                      caseNumber: str(l["case_number"]), caseYear: str(l["case_year"]))
            }
            return j(MatterRecord.listOfDatesHtml(project: project, linkedCase: linked, entries: chronology(i)))
        case "totalsFromLedger": return totals(MatterRecord.totalsFromLedger(array(i["ledger"]).map { entry($0) }))

        // projectMeta.js, trackedCases.js, trackCase.js, lookupModel.js
        case "bannerPresetOf":
            return j(MatterMeta.bannerPreset(banner: str(i["project"]?["banner"]), color: str(i["project"]?["color"])).rawValue)
        case "practiceAreaLabel": return j(MatterMeta.practiceAreaLabel(str(i["key"])))
        case "caseRefOf":
            let p = i["project"]
            return j(MatterMeta.caseRef(caseNumber: str(p?["case_number"]), caseType: str(p?["case_type"]),
                                        caseYear: str(p?["case_year"]), cnr: str(p?["cnr"])))
        case "activityAt":
            let p = i["project"]
            let at = MatterMeta.activityAt(updated: str(p?["updated_at"]), created: str(p?["created_at"]),
                                           lastActivity: str(p?["last_activity"]))
            return j(at.map { ($0.timeIntervalSince1970 * 1000).rounded() } ?? 0)
        case "caseStatusKey": return j(MatterMeta.caseStatusKey(str(i["status"])).rawValue)
        case "bannerForCase": return j(MatterMeta.bannerForCase(str(i["caseId"]) ?? "").rawValue)
        case "matterByCase":
            let projects = array(i["projects"]).map {
                (id: str($0["id"]) ?? "", linkedCaseID: str($0["linked_case_id"]), createdAt: str($0["created_at"]))
            }
            return .object(MatterMeta.matterByCase(projects).mapValues(JSONValue.string))
        case "trackedCaseRow":
            let k = object(i["kase"])
            let team: (name: String?, memberCount: Int)? = i["team"] == .null || i["team"] == nil
                ? nil : (name: str(i["team"]?["name"]), memberCount: int(i["team"]?["member_count"]) ?? 0)
            let r = MatterMeta.trackedCaseRow(MatterMeta.TrackedCase(
                id: str(k["id"]) ?? "", title: str(k["title"]), parties: str(k["parties"]), status: str(k["status"]),
                courtName: str(k["court_name"]), courtType: str(k["court_type"]), caseType: str(k["case_type"]),
                caseNumber: str(k["case_number"]), caseYear: str(k["case_year"]), cnr: str(k["cnr"]),
                diaryNumber: str(k["diary_number"]), stage: str(k["stage"]), nextHearingDate: str(k["next_hearing_date"]),
                teamName: str(k["team_name"]), createdAt: str(k["created_at"])), team: team)
            return .object([
                "id": j(r.id), "kind": j("case"), "caseId": j(r.caseID), "name": j(r.name), "status": j(r.status.rawValue),
                "courtStatus": j(r.courtStatus), "banner": j(r.banner.rawValue), "practice_area": .null,
                "forum_name": j(r.forumName), "caseRef": j(r.caseRef), "case_type": j(r.caseType),
                "case_number": j(r.caseNumber), "case_year": j(r.caseYear), "cnr": j(r.cnr), "diary_number": j(r.diaryNumber),
                "parties": j(r.parties), "stage": j(r.stage), "next_hearing_date": j(r.nextHearingDate),
                "sharedWith": j(r.sharedWith), "created_at": j(r.createdAt),
            ])
        case "casePayload":
            let p = pick(i["pick"]).payload
            let all: [String: String?] = [
                "courtType": p.courtType, "courtCode": p.courtCode, "courtName": p.courtName, "caseType": p.caseType,
                "caseNumber": p.caseNumber, "caseYear": p.caseYear, "cnr": p.cnr, "diaryNumber": p.diaryNumber,
                "title": p.title, "parties": p.parties, "judge": p.judge, "status": p.status, "stage": p.stage,
                "nextHearingDate": p.nextHearingDate, "scrapeRef": p.scrapeRef,
            ]
            return .object(all.compactMapValues { $0 }.mapValues(JSONValue.string))
        case "extIdOf": return j(MatterMeta.extID(of: pick(i["body"])))
        case "canon": return j(MatterMeta.canon(str(i["value"])))
        case "findTrackedCase":
            let cases = array(i["cases"]).map { c in
                MatterMeta.TrackedCaseCandidate(
                    id: str(c["id"]) ?? "", teamID: str(c["team_id"]), extID: str(c["ext_id"]), cnr: str(c["cnr"]),
                    diaryNumber: str(c["diary_number"]), caseNumber: str(c["case_number"]), caseYear: str(c["case_year"]),
                    caseType: str(c["case_type"]), courtCode: str(c["court_code"]), courtName: str(c["court_name"]))
            }
            return j(MatterMeta.findTrackedCase(pick(i["pick"]), in: cases,
                                                ownedTeamIDs: Set(array(i["ownedTeamIds"]).compactMap { str($0) })))
        case "lookup.caseNumberOf":
            let r = i["record"]
            return j(MatterMeta.lookupCaseNumber(caseType: str(r?["caseType"]), caseNumber: str(r?["caseNumber"]),
                                                 caseYear: str(r?["caseYear"])))
        case "lookup.titleOf":
            let r = i["record"]
            return j(MatterMeta.lookupTitle(title: str(r?["title"]), caseType: str(r?["caseType"]),
                                            caseNumber: str(r?["caseNumber"]), caseYear: str(r?["caseYear"])))
        case "sideKeysFor":
            let keys = MatterMeta.sideKeys(caseType: str(i["caseType"]))
            return j([keys.0.rawValue, keys.1.rawValue])
        default:
            return nil
        }
    }
}

private extension JSONValue {
    /// `{ok: "123"}` from `attempt` → `{ok: 123}`: the paise travel as a number.
    var paiseAnswer: JSONValue {
        if case .object(let o) = self, case .string(let s)? = o["ok"], let n = Double(s) {
            return .object(["ok": .number(n)])
        }
        return self
    }
}
