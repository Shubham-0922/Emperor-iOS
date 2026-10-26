import XCTest
@testable import EmperorCore

/// The three analysis tools held to the platform's own shaping code
/// (`scripts/generate-analysis-fixtures.mjs`): every normalised value, every derived number, every
/// export, for the server's samples, the pages' samples and a set of messy answers. Regenerate on
/// a platform change; never edit.
final class AnalysisGoldenTests: XCTestCase {

    private func load(_ name: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: try parityFixture("analysis", name))
    }

    private func cases(_ g: JSONValue) -> [JSONValue] {
        if case .array(let items)? = g["cases"] { return items }
        return []
    }

    private func list(_ v: JSONValue?) -> [JSONValue] {
        if case .array(let items)? = v { return items }
        return []
    }

    // MARK: - Devil's Advocate

    func testDevilsAdvocateNormalisesAsTheWebDoes() throws {
        let g = try load("da-golden")
        XCTAssertGreaterThan(cases(g).count, 8)
        for c in cases(g) {
            let id = c["id"]?.stringValue ?? "?"
            let report = DevilsAdvocateReport.normalise(c["input"])
            guard let expected = c["normalised"], expected != .null else {
                XCTAssertNil(report, id)
                continue
            }
            let r = try XCTUnwrap(report, id)
            XCTAssertEqual(J.report(r), expected, id)
            let derived = c["derived"]
            XCTAssertEqual(J.counts(r.countBySeverity), derived?["countBySeverity"], id)
            XCTAssertEqual(.string(r.exposureBand), derived?["exposureBand"], id)
            XCTAssertEqual(.array(r.categoryRows.map(J.categoryRow)), derived?["categoryRows"], id)
            XCTAssertEqual(
                .array(r.matrixCells.filter { !$0.spots.isEmpty }.map(J.matrixCell)), derived?["matrixCells"], id)
            XCTAssertEqual(J.readiness(r.readinessCounts), derived?["readinessCounts"], id)
        }
    }

    func testDevilsAdvocateVocabulary() throws {
        let g = try load("da-golden")
        for b in list(g["exposureBands"]) {
            XCTAssertEqual(
                DevilsAdvocateReport.exposureBand(Int(b["score"]?.doubleValue ?? -1)), b["band"]?.stringValue)
        }
        for c in list(g["categoryLabels"]) {
            let key = c["key"]?.stringValue ?? ""
            XCTAssertEqual(DevilsAdvocateReport.categoryLabel(key), c["label"]?.stringValue, key)
        }
        for s in list(g["severities"]) {
            XCTAssertEqual(DevilsAdvocateReport.normaliseSeverity(s["v"]).rawValue, s["out"]?.stringValue, "\(String(describing: s["v"]))")
        }
        for s in list(g["readiness"]) {
            XCTAssertEqual(DevilsAdvocateReport.normaliseReadiness(s["v"]).rawValue, s["out"]?.stringValue, "\(String(describing: s["v"]))")
        }
        for s in list(g["scales"]) {
            XCTAssertEqual(
                Double(DevilsAdvocateReport.normaliseScale(s["v"])), s["out"]?.doubleValue, "\(String(describing: s["v"]))")
        }
        let india = try XCTUnwrap(TimeZone(identifier: "Asia/Kolkata"))
        for m in list(g["madeOn"]) {
            let date = try XCTUnwrap(WireDate.parse(m["iso"]?.stringValue))
            XCTAssertEqual(AnalysisHistoryFormat.madeOn(date, timeZone: india), m["text"]?.stringValue)
        }
    }

    func testTheServersOwnReportReadsWhole() throws {
        let raw = try load("server-devils-advocate")
        let r = try XCTUnwrap(DevilsAdvocateReport.normalise(raw))
        XCTAssertFalse(r.weakSpots.isEmpty)
        XCTAssertFalse(r.questions.isEmpty)
        let html = DevilsAdvocateExport.html(r, madeOn: "27 October 2026")
        XCTAssertTrue(html.contains("Your weak spots, ranked"))
        XCTAssertTrue(html.contains(DevilsAdvocateExport.esc(r.weakSpots[0].title)))
        XCTAssertFalse(html.contains("<script"))
    }

    // MARK: - Doc Index

    func testDocIndexNormalisesAsTheWebDoes() throws {
        let g = try load("doc-index-golden")
        XCTAssertGreaterThan(cases(g).count, 8)
        for c in cases(g) {
            let id = c["id"]?.stringValue ?? "?"
            let index = DocIndex.normalise(c["input"])
            guard let expected = c["normalised"], expected != .null else {
                XCTAssertNil(index, id)
                continue
            }
            let n = try XCTUnwrap(index, id)
            XCTAssertEqual(.string(n.id), expected["id"], id)
            XCTAssertEqual(.string(n.label), expected["label"], id)
            XCTAssertEqual(n.filterKey.map(JSONValue.string) ?? .null, expected["filterKey"], id)
            XCTAssertEqual(.string(n.filterLabel), expected["filterLabel"], id)
            XCTAssertEqual(n.pagesKey.map(JSONValue.string) ?? .null, expected["pagesKey"], id)
            XCTAssertEqual(.string(n.rationale), expected["rationale"], id)
            checkFlag(n.flag, expected["flag"], id)
            XCTAssertEqual(.array(n.columns.map(J.column)), expected["columns"], id)
            XCTAssertEqual(.array(n.rows.map { J.row($0, n.columns) }), expected["rows"], id)

            let cellText = n.rows.map { row in JSONValue.array(n.columns.map { .string(DocIndex.cellText($0, row)) }) }
            XCTAssertEqual(.array(cellText), c["cellText"], id)
            for column in n.columns {
                let sorts = c["sorts"]?[column.key]
                let asc = AnalysisJS.stableSorted(n.rows) { DocIndex.compareCells(column, $0, $1, descending: false) }
                let desc = AnalysisJS.stableSorted(n.rows) { DocIndex.compareCells(column, $0, $1, descending: true) }
                XCTAssertEqual(.array(asc.map { .string($0.id) }), sorts?["asc"], "\(id) \(column.key) asc")
                XCTAssertEqual(.array(desc.map { .string($0.id) }), sorts?["desc"], "\(id) \(column.key) desc")
            }
            XCTAssertEqual(.string(DocIndex.toCSV(columns: n.columns, rows: n.rows)), c["csv"], id)
            XCTAssertEqual(n.flaggedCount.map { JSONValue.number(Double($0)) } ?? .null, c["flagged"], id)
            let counts = n.filterCounts.map { JSONValue.object(["value": .string($0.value), "count": .number(Double($0.count))]) }
            let expectedCounts = list(c["filterCounts"]).map { item -> JSONValue in
                .object(["value": .string(AnalysisJS.string(item["value"])), "count": item["count"] ?? .null])
            }
            XCTAssertEqual(counts, expectedCounts, id)
            let totals = n.totals(shown: n.rows).map { JSONValue.object(["key": .string($0.column.key), "sum": .number($0.sum)]) }
            XCTAssertEqual(.array(totals), c["totals"], id)
            for s in list(c["search"]) {
                let q = s["q"]?.stringValue ?? ""
                let ids = n.rows(query: q, filter: nil, sortKey: nil, descending: false).map { JSONValue.string($0.id) }
                XCTAssertEqual(.array(ids), s["ids"], "\(id) search \(q)")
            }
            for t in list(c["tones"]) {
                let column = try XCTUnwrap(n.columns.first { $0.key == t["key"]?.stringValue }, id)
                XCTAssertEqual(DocIndex.tone(column, t["value"]?.stringValue ?? ""), t["tone"]?.stringValue, id)
            }
        }
    }

    private func checkFlag(_ flag: DocIndex.Flag?, _ expected: JSONValue?, _ id: String) {
        guard let expected, expected != .null else {
            XCTAssertNil(flag, id)
            return
        }
        guard let flag else { return XCTFail("\(id): no flag") }
        XCTAssertEqual(flag.key, AnalysisJS.string(expected["key"]), id)
        XCTAssertEqual(flag.nonEmpty, AnalysisJS.truthy(expected["nonEmpty"]), id)
        XCTAssertEqual(flag.label, expected["label"]?.stringValue, id)
        XCTAssertEqual(flag.values.map(JSONValue.array), expected["in"], id)
    }

    func testDocIndexFormatting() throws {
        let g = try load("doc-index-golden")
        for f in list(g["fmtInr"]) {
            XCTAssertEqual(DocIndex.fmtINR(f["n"]?.doubleValue), f["text"]?.stringValue, "\(String(describing: f["n"]))")
        }
        for f in list(g["fmtDate"]) {
            XCTAssertEqual(DocIndex.fmtDate(f["iso"]?.stringValue), f["text"]?.stringValue, "\(String(describing: f["iso"]))")
        }
        for f in list(g["fmtPages"]) {
            XCTAssertEqual(DocIndex.fmtPages(f["n"]?.doubleValue), f["text"]?.stringValue, "\(String(describing: f["n"]))")
        }
    }

    // MARK: - List of Dates

    func testListOfDatesNormalisesAsTheWebDoes() throws {
        let g = try load("list-of-dates-golden")
        XCTAssertGreaterThan(cases(g).count, 5)
        for c in cases(g) {
            let id = c["id"]?.stringValue ?? "?"
            let chart = DateChart.normalise(c["input"])
            XCTAssertEqual(J.chart(chart), c["normalised"], id)
            XCTAssertEqual(J.sum(chart.sum), c["sum"], id)
            XCTAssertEqual(.string(chart.title), c["title"], id)
            XCTAssertEqual(.array(DateChart.byYear(chart.entries).map(J.yearRow)), c["byYear"], id)
            XCTAssertEqual(.string(chart.asPlainText()), c["plainText"], id)
            XCTAssertEqual(.string(chart.asPlainText(chart.entries.filter { $0.cat == .adverse })), c["plainTextAdverse"], id)
            XCTAssertEqual(.string(chart.asWordHTML()), c["wordHtml"], id)
            XCTAssertEqual(.string(chart.fileStem), c["fileStem"], id)
            XCTAssertEqual(.string(chart.matterLine), c["matterLine"], id)
            XCTAssertEqual(.string(chart.eventsHead), c["eventsHead"], id)
            XCTAssertEqual(.array(chart.timelineItems.map(J.timelineItem)), c["timeline"], id)
            for m in list(c["matches"]) {
                let q = m["q"]?.stringValue ?? ""
                let ids = chart.entries.filter { DateChart.matches($0, q) }.map { JSONValue.string($0.id) }
                XCTAssertEqual(.array(ids), m["ids"], "\(id) \(q)")
            }
        }
    }

    func testListOfDatesReading() throws {
        let g = try load("list-of-dates-golden")
        for d in list(g["normDay"]) {
            XCTAssertEqual(DateChart.normDay(d["v"]), d["out"]?.stringValue, "\(String(describing: d["v"]))")
        }
        for p in list(g["parseRich"]) {
            let runs = DateChart.parseRich(p["v"]).map { JSONValue.object(["t": .string($0.text), "b": .bool($0.bold)]) }
            XCTAssertEqual(.array(runs), p["out"], "\(String(describing: p["v"]))")
        }
        for d in list(g["days"]) {
            let day = d["day"]?.stringValue ?? ""
            XCTAssertEqual(DateChart.dmy(day), d["dmy"]?.stringValue, day)
            XCTAssertEqual(DateChart.shortDate(day), d["shortDate"]?.stringValue, day)
            XCTAssertEqual(DateChart.fullDate(day), d["fullDate"]?.stringValue, day)
            XCTAssertEqual(DateChart.yearOf(day), d["yearOf"]?.stringValue, day)
        }
    }

    // MARK: - History wording

    func testHistoryWording() throws {
        let g = try load("history-golden")
        let zone = try XCTUnwrap(TimeZone(identifier: try XCTUnwrap(g["timeZone"]?.stringValue)))
        let now = try XCTUnwrap(WireDate.parse(g["now"]?.stringValue))
        for a in list(g["ago"]) {
            XCTAssertEqual(
                AnalysisHistoryFormat.ago(a["iso"]?.stringValue, now: now, timeZone: zone), a["text"]?.stringValue,
                a["iso"]?.stringValue ?? "")
        }
        for f in list(g["fullDate"]) {
            XCTAssertEqual(
                AnalysisHistoryFormat.fullDate(f["iso"]?.stringValue, timeZone: zone), f["text"]?.stringValue,
                f["iso"]?.stringValue ?? "")
        }
        for f in list(g["fileLine"]) {
            let names = list(f["names"]).compactMap(\.stringValue)
            XCTAssertEqual(AnalysisHistoryFormat.fileLine(names), f["text"]?.stringValue)
        }
        for r in list(g["runTitle"]) {
            let run = AnalysisRunSummary(
                id: "x", title: r["run"]?["title"]?.stringValue,
                fileNames: r["run"]?["fileNames"].map { list($0).compactMap(\.stringValue) })
            XCTAssertEqual(run.displayTitle, r["text"]?.stringValue)
        }
    }
}

/// Swift values written as the JSON the generator writes, for comparison.
private enum J {
    static func n(_ i: Int) -> JSONValue { .number(Double(i)) }
    static func s(_ t: String) -> JSONValue { .string(t) }
    static func opt(_ i: Int?) -> JSONValue { i.map(n) ?? .null }
    static func strings(_ list: [String]) -> JSONValue { .array(list.map(s)) }

    static func report(_ r: DevilsAdvocateReport) -> JSONValue {
        .object([
            "matter": .object([
                "title": s(r.matter.title), "forum": s(r.matter.forum), "number": s(r.matter.number),
                "client": s(r.matter.client), "date": s(r.matter.date),
            ]),
            "exposureScore": n(r.exposureScore),
            "oneMinute": strings(r.oneMinute),
            "weakSpots": .array(r.weakSpots.map { w in
                .object([
                    "id": n(w.id), "severity": s(w.severity.rawValue), "category": s(w.category),
                    "likelihood": n(w.likelihood), "impact": n(w.impact), "title": s(w.title), "why": s(w.why),
                    "where": strings(w.where), "say": s(w.say), "fix": s(w.fix),
                ])
            }),
            "questions": .array(r.questions.map { q in
                .object(["q": s(q.q), "why": s(q.why), "answer": s(q.answer), "readiness": s(q.readiness.rawValue), "spot": opt(q.spot)])
            }),
            "docGaps": .array(r.docGaps.map { d in
                .object(["doc": s(d.doc), "who": s(d.who), "how": s(d.how), "when": s(d.when), "spot": opt(d.spot)])
            }),
            "authorities": .array(r.authorities.map { a in
                .object([
                    "name": s(a.name), "court": s(a.court), "year": s(a.year), "pinCite": s(a.pinCite),
                    "holds": s(a.holds), "distinguish": s(a.distinguish), "against": opt(a.against), "verify": .bool(a.verify),
                ])
            }),
            "checklist": .array(r.checklist.map { .object(["id": s($0.id), "text": s($0.text), "done": .bool($0.done)]) }),
        ])
    }

    static func counts(_ c: DevilsAdvocateReport.SeverityCounts) -> JSONValue {
        .object(["serious": n(c.serious), "moderate": n(c.moderate), "minor": n(c.minor)])
    }

    static func categoryRow(_ r: DevilsAdvocateReport.CategoryRow) -> JSONValue {
        .object(["key": s(r.key), "label": s(r.label), "by": counts(r.by), "count": n(r.count), "weight": n(r.weight)])
    }

    static func matrixCell(_ c: DevilsAdvocateReport.MatrixCell) -> JSONValue {
        .object(["likelihood": n(c.likelihood), "impact": n(c.impact), "score": n(c.score), "spots": .array(c.spots.map { n($0.id) })])
    }

    static func readiness(_ c: DevilsAdvocateReport.ReadinessCounts) -> JSONValue {
        .object(["all": n(c.all), "ready": n(c.ready), "work": n(c.work), "gap": n(c.gap)])
    }

    static func column(_ c: DocIndex.Column) -> JSONValue {
        .object([
            "key": s(c.key), "label": s(c.label), "type": s(c.type.rawValue), "width": .number(c.width),
            "description": s(c.description), "pin": .bool(c.pin), "strong": .bool(c.strong), "total": .bool(c.total),
            "tones": c.tones.map { .object($0.mapValues(JSONValue.string)) } ?? .null,
            "order": c.order.map { .array($0.map { $0.map(JSONValue.string) ?? .null }) } ?? .null,
        ])
    }

    static func row(_ r: DocIndex.Row, _ columns: [DocIndex.Column]) -> JSONValue {
        var o: [String: JSONValue] = ["__id": s(r.id)]
        for c in columns { o[c.key] = .null }
        for (key, cell) in r.cells {
            switch cell {
            case .text(let t): o[key] = s(t)
            case .number(let v): o[key] = .number(v)
            case .tags(let t): o[key] = strings(t)
            }
        }
        return .object(o)
    }

    static func chart(_ c: DateChart) -> JSONValue {
        .object([
            "entries": .array(c.entries.map { e in
                .object([
                    "id": s(e.id), "day": s(e.day), "cat": s(e.cat.rawValue), "text": s(e.text), "short": s(e.short),
                    "label": s(e.label), "upcoming": .bool(e.upcoming), "hay": s(e.hay),
                ])
            }),
            "matter": .object(["title": s(c.matter.title), "number": s(c.matter.number), "forum": s(c.matter.forum)]),
            "inSum": s(c.inSum),
            "limitation": c.limitation.map { .object(["headline": s($0.headline), "note": s($0.note)]) } ?? .null,
            "chartTitleOverride": s(c.chartTitleOverride),
            "cats": .object(Dictionary(uniqueKeysWithValues: DateChart.Category.allCases.map { k in
                let w = c.words(k)
                return (k.rawValue, JSONValue.object(["label": s(w.label), "chip": s(w.chip), "who": s(w.who)]))
            })),
        ])
    }

    static func sum(_ s: DateChart.Summary) -> JSONValue {
        .object([
            "total": n(s.total), "rules": n(s.rules), "ours": n(s.ours), "others": n(s.others),
            "adverse": n(s.adverse), "from": .string(s.from), "to": .string(s.to), "all": n(s.all),
        ])
    }

    static func yearRow(_ r: DateChart.YearRow) -> JSONValue {
        .object(["year": s(r.year), "rules": .array(r.rules.map { s($0.id) }), "events": .array(r.events.map { s($0.id) })])
    }

    static func timelineItem(_ i: DateChart.TimelineItem) -> JSONValue {
        if let e = i.entry { return .object(["entry": s(e.id), "next": .bool(i.next)]) }
        return .object(["year": s(i.year ?? "")])
    }
}
