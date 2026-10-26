import XCTest
@testable import EmperorCore

/// `LibraryDisplay` and `JudgmentText` held to the web's own Library helpers, run under Node by
/// `scripts/generate-library-fixtures.mjs`. When one fails after a platform change, regenerate the
/// fixture; do not edit it to match.
final class LibraryDisplayGoldenTests: XCTestCase {

    private func fixture() throws -> [String: Any] {
        let data = try parityFixture("library", "display")
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func doc(_ object: Any) throws -> LibraryDoc {
        let data = try JSONSerialization.data(withJSONObject: object)
        return try JSONDecoder().decode(LibraryDoc.self, from: data)
    }

    private func strings(_ any: Any?) -> [String] { (any as? [Any])?.compactMap { $0 as? String } ?? [] }

    func testThemesAndOrder() throws {
        let f = try fixture()
        XCTAssertEqual(strings(f["order"]), LibraryCategoryKey.order)
        XCTAssertEqual(f["coverInk"] as? String, LibraryDisplay.coverInk)
        let themes = try XCTUnwrap(f["themes"] as? [String: [String: Any]])
        for (key, t) in themes {
            let mine = LibraryDisplay.theme(key)
            XCTAssertEqual(mine.label, t["label"] as? String, key)
            XCTAssertEqual(mine.cap, t["cap"] as? String, key)
            XCTAssertEqual(mine.untitled, t["untitled"] as? String, key)
            XCTAssertEqual(mine.blurb, t["blurb"] as? String, key)
            XCTAssertEqual(mine.cloth, strings(t["cloth"]), key)
        }
        for h in try XCTUnwrap(f["hashes"] as? [[String: Any]]) {
            let value = (h["value"] as? String) ?? (h["value"] as? Int).map(String.init) ?? ""
            XCTAssertEqual(Int(LibraryDisplay.hashOf(value)), h["hash"] as? Int, value)
        }
        XCTAssertEqual(strings(f["tabOrder"]), LibraryDisplay.tabOrder)
        XCTAssertEqual(strings(f["courtOrder"]), LibraryDisplay.courtOrder)
        let has = try XCTUnwrap(f["hasFilters"] as? [[String: String]])
        XCTAssertEqual(has.map { $0["key"] ?? "" }, LibraryDisplay.hasFilters.map(\.key))
        XCTAssertEqual(has.map { $0["label"] ?? "" }, LibraryDisplay.hasFilters.map(\.label))
    }

    func testEveryRowReadsAsOnTheWeb() throws {
        let rows = try XCTUnwrap(fixture()["rows"] as? [[String: Any]])
        XCTAssertGreaterThan(rows.count, 30)
        for row in rows {
            let d = try doc(row["doc"] as Any)
            let id = "doc \(d.id)"
            XCTAssertEqual(LibraryDisplay.tidyTitle(d), row["tidyTitle"] as? String, id)
            XCTAssertEqual(LibraryDisplay.isUntitled(d), row["isUntitled"] as? Bool, id)
            XCTAssertEqual(LibraryDisplay.docMeta(d), strings(row["docMeta"]), id)
            XCTAssertEqual(LibraryDisplay.isTextDoc(d), row["isTextDoc"] as? Bool, id)
            XCTAssertEqual(LibraryDisplay.caseTitleText(d), row["caseTitleText"] as? String, id)
            XCTAssertEqual(LibraryDisplay.caseNumberText(d), row["caseNumberText"] as? String, id)
            XCTAssertEqual(LibraryDisplay.actTitle(d), row["actTitle"] as? String, id)
            let split = try XCTUnwrap(row["splitTitle"] as? [String: String])
            let mine = LibraryDisplay.splitTitle(d)
            XCTAssertEqual(mine.name, split["name"], id)
            XCTAssertEqual(mine.year, split["year"], id)
            XCTAssertEqual(LibraryDisplay.isRepealed(d), row["isRepealed"] as? Bool, id)
            XCTAssertEqual(LibraryDisplay.actKicker(d), row["actKicker"] as? String, id)
            XCTAssertEqual(LibraryDisplay.actTabLabel(d, kind: d.kind == "amendments" ? "amendments" : "act"),
                           row["actTabLabel"] as? String, id)
            let j = try XCTUnwrap(row["jurisdiction"] as? [String: Any])
            let jm = LibraryDisplay.jurisdictionOf(d)
            XCTAssertEqual(jm.value, j["value"] as? String, id)
            XCTAssertEqual(jm.label, j["label"] as? String, id)
            XCTAssertEqual(jm.short, j["short"] as? String, id)
            XCTAssertEqual(jm.central, j["central"] as? Bool, id)
            XCTAssertEqual(LibraryDisplay.copySource(d), row["copySource"] as? String, id)
            XCTAssertEqual(LibraryDisplay.actCloth(d), row["actCloth"] as? String, id)
            XCTAssertEqual(LibraryDisplay.captionMeta(d), strings(row["captionMeta"]), id)
            XCTAssertEqual(LibraryDisplay.captionMeta(d, withSeries: false, withSize: true),
                           strings(row["captionMetaSized"]), id)
            XCTAssertEqual(LibraryDisplay.referenceLine(d), row["referenceLine"] as? String, id)
            XCTAssertEqual(LibraryDisplay.volumeTitle(d), row["volumeTitle"] as? String, id)
            if let label = row["volumeLabel"] as? [String: String] {
                let v = try XCTUnwrap(LibraryDisplay.volumeLabel(d), id)
                XCTAssertEqual(v.top, label["top"], id)
                XCTAssertEqual(v.bottom, label["bottom"], id)
            } else {
                XCTAssertNil(LibraryDisplay.volumeLabel(d), id)
            }
            XCTAssertEqual(LibraryDisplay.citationLine(d), row["citationLine"] as? String, id)

            let cover = try XCTUnwrap(row["coverFields"] as? [String: Any])
            let fields = LibraryDisplay.coverFields(d)
            XCTAssertEqual(fields.kicker, cover["kicker"] as? String, id)
            XCTAssertEqual(fields.title, cover["title"] as? String, id)
            XCTAssertEqual(fields.parties, (cover["parties"] as? [Any]).map(strings), id)
            XCTAssertEqual(fields.foot, strings(cover["foot"]), id)

            if let court = row["court"] as? [String: String] {
                let c = LibraryDisplay.courtInfo(d.court, label: d.courtLabel)
                XCTAssertEqual(c.name, court["name"], id)
                XCTAssertEqual(c.short, court["short"], id)
                XCTAssertEqual(c.mono, court["mono"], id)
            }
        }
    }

    func testPartiesNumbersDaysCountsAndSizes() throws {
        let f = try fixture()
        for p in try XCTUnwrap(f["parties"] as? [[String: String]]) {
            XCTAssertEqual(LibraryDisplay.tidyParty(p["name"]), p["text"], p["name"] ?? "")
        }
        for c in try XCTUnwrap(f["caseNumbers"] as? [[String: Any]]) {
            let h = c["header"] as? [String: String] ?? [:]
            XCTAssertEqual(LibraryDisplay.caseNumberText(caseType: h["caseType"], caseNumber: h["caseNumber"]),
                           c["text"] as? String, "\(h)")
        }
        for d in try XCTUnwrap(f["days"] as? [[String: String]]) {
            XCTAssertEqual(LibraryDisplay.fmtDay(d["iso"]), d["text"], d["iso"] ?? "")
        }
        for c in try XCTUnwrap(f["counts"] as? [[String: Any]]) {
            let n = try XCTUnwrap(c["n"] as? Double)
            XCTAssertEqual(LibraryDisplay.fmtCount(n), c["text"] as? String, "\(n)")
            if n == n.rounded() { XCTAssertEqual(LibraryDisplay.fmtCount(Int(n)), c["text"] as? String) }
        }
        for c in try XCTUnwrap(f["countParts"] as? [[String: Any]]) {
            let counts = c["tabCounts"] as? [String: Int] ?? [:]
            XCTAssertEqual(
                LibraryDisplay.countParts(counts, withEditions: c["withEditions"] as? Bool ?? false, first: c["first"] as? String),
                strings(c["parts"]), "\(counts)")
        }
        for s in try XCTUnwrap(f["sizes"] as? [[String: Any]]) {
            let bytes = Int(try XCTUnwrap(s["bytes"] as? Double))
            XCTAssertEqual(LibraryDisplay.actSize(bytes), s["act"] as? String, "\(bytes)")
            XCTAssertEqual(LibraryDisplay.bookSize(bytes), s["book"] as? String, "\(bytes)")
        }
        for s in try XCTUnwrap(f["series"] as? [[String: String]]) {
            XCTAssertEqual(LibraryDisplay.seriesName(s["name"]), s["text"])
        }
    }

    func testDecadesAndLatest() throws {
        let f = try fixture()
        let decades = try XCTUnwrap(f["decades"] as? [String: Any])
        let docs = try (decades["docs"] as? [Any] ?? []).map(doc)
        let groups = try XCTUnwrap(decades["groups"] as? [[String: Any]])
        let mine = LibraryDisplay.groupByDecade(docs, thisYear: 2026)
        XCTAssertEqual(mine.map(\.key), groups.map { $0["key"] as? String ?? "" })
        XCTAssertEqual(mine.map(\.label), groups.map { $0["label"] as? String ?? "" })
        XCTAssertEqual(mine.map { $0.items.map(\.id) }, groups.map { $0["ids"] as? [Int] ?? [] })

        for c in try XCTUnwrap(f["latest"] as? [[String: Any]]) {
            let list = try (c["docs"] as? [Any] ?? []).map(doc)
            XCTAssertEqual(LibraryDisplay.latestID(list), c["latest"] as? Int)
        }
    }

    func testPlainTextFallbackFindAndParagraphs() throws {
        let plain = try XCTUnwrap(fixture()["plain"] as? [String: Any])
        let text = try XCTUnwrap(plain["text"] as? String)
        let paragraphs = JudgmentText.paragraphs(fromStoredText: text)
        XCTAssertEqual(paragraphs, strings(plain["paragraphs"]))
        let blocks = JudgmentText.blocks(fromParagraphs: paragraphs)
        let expected = try XCTUnwrap(plain["blocks"] as? [[String: String]])
        XCTAssertEqual(blocks.map(\.id), expected.map { $0["id"] ?? "" })
        XCTAssertEqual(blocks.map(\.text), expected.map { $0["text"] ?? "" })
        XCTAssertEqual(blocks.map(\.n), expected.map { $0["n"] })
        for c in try XCTUnwrap(plain["find"] as? [[String: Any]]) {
            let q = c["query"] as? String ?? ""
            let hits = JudgmentText.hits(in: blocks, query: q).hits.map { [$0.block, $0.start, $0.end] }
            XCTAssertEqual(hits, c["hits"] as? [[Int]], q)
        }
        for c in try XCTUnwrap(plain["paras"] as? [[String: Any]]) {
            let n = c["n"] as? String ?? ""
            let index = c["index"] as? Int ?? -1
            XCTAssertEqual(JudgmentText.paragraphIndex(blocks, n), index < 0 ? nil : index, n)
        }
    }
}
