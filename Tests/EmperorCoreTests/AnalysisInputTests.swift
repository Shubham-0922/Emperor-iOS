import XCTest
@testable import EmperorCore

final class AnalysisInputTests: XCTestCase {

    func testAMattersFolderIsRefused() {
        let (accepted, refused) = AnalysisInput.usable([
            ChatAttachment(name: "Plaint.pdf", folderName: "_projects/p1"),
            ChatAttachment(name: "Order.pdf", folderName: "Bakshi/_Projects_old"),
            ChatAttachment(name: "Ok.pdf", folderName: "Bakshi"),
        ])
        XCTAssertEqual(accepted.map(\.name), ["Ok.pdf"])
        XCTAssertEqual(refused.map(\.reason), [AnalysisInput.matterFolder, AnalysisInput.matterFolder])
    }

    func testADocumentWithoutAFolderIsRefused() {
        let (accepted, refused) = AnalysisInput.usable([
            ChatAttachment(name: "Loose.pdf", folderName: nil),
            ChatAttachment(name: "Blank.pdf", folderName: "  "),
        ])
        XCTAssertTrue(accepted.isEmpty)
        XCTAssertEqual(refused.map(\.reason), [AnalysisInput.noFolder, AnalysisInput.noFolder])
    }

    func testANameThatIsAPathIsRefused() {
        let names = ["a/b.pdf", "a\\b.pdf", "..", "bad\u{0}.pdf", "tab\t.pdf", ""]
        let (accepted, refused) = AnalysisInput.usable(names.map { ChatAttachment(name: $0, folderName: "F") })
        XCTAssertTrue(accepted.isEmpty)
        XCTAssertEqual(refused.count, names.count)
        XCTAssertTrue(refused.allSatisfy { $0.reason == AnalysisInput.notAPlainName })
    }

    func testTheSameDocumentTwiceGoesOnce() {
        let (accepted, refused) = AnalysisInput.usable([
            ChatAttachment(name: "A.pdf", folderName: "F"),
            ChatAttachment(name: "A.pdf", folderName: "F"),
            ChatAttachment(name: "A.pdf", folderName: "G"),
        ])
        XCTAssertEqual(accepted.map(\.folderName), ["F", "G"])
        XCTAssertTrue(refused.isEmpty)
    }

    func testAtMostTenGo() {
        let files = (1...12).map { ChatAttachment(name: "D\($0).pdf", folderName: "F") }
        let (accepted, refused) = AnalysisInput.usable(files)
        XCTAssertEqual(accepted.count, 10)
        XCTAssertEqual(refused.map(\.file.name), ["D11.pdf", "D12.pdf"])
        XCTAssertTrue(refused.allSatisfy { $0.reason == "At most 10 documents at a time" })
    }

    func testTheNoteCounterAppearsNearTheLimit() {
        XCTAssertNil(AnalysisInput.referenceCounter(String(repeating: "a", count: 1800)))
        XCTAssertEqual(AnalysisInput.referenceCounter(String(repeating: "a", count: 1801)), "1,801 / 2,000")
        XCTAssertFalse(AnalysisInput.isReferenceTooLong("  " + String(repeating: "a", count: 2000) + "  "))
    }

    func testTheProvenanceLine() {
        XCTAssertEqual(AnalysisHistoryFormat.provenance(["a.pdf"]), "Read 1 document: a.pdf")
        XCTAssertEqual(AnalysisHistoryFormat.provenance(["a", "b", "c", "d"]), "Read 4 documents: a, b and 2 more")
    }

    // MARK: - What is on screen

    private static let index = DocIndex.normalise(.object([
        "filterKey": .string("type"),
        "columns": .array([
            .object(["key": .string("doc"), "label": .string("Document"), "type": .string("text")]),
            .object(["key": .string("type"), "label": .string("Type"), "type": .string("badge")]),
            .object(["key": .string("pp"), "label": .string("Pages"), "type": .string("pages")]),
        ]),
        "rows": .array([
            .object(["doc": .string("Plaint"), "type": .string("Pleading"), "pp": .number(12)]),
            .object(["doc": .string("Notice"), "type": .string("Notice"), "pp": .number(3)]),
            .object(["doc": .string("Reply"), "type": .string("Pleading"), "pp": .number(7)]),
        ]),
    ]))!

    func testTheIndexSortsAscendingDescendingThenNot() {
        var state = DocIndexViewState()
        state.toggleSort("pp")
        XCTAssertEqual(state.rows(Self.index).map(\.id), ["r1", "r2", "r0"])
        state.toggleSort("pp")
        XCTAssertEqual(state.rows(Self.index).map(\.id), ["r0", "r2", "r1"])
        state.toggleSort("pp")
        XCTAssertNil(state.sortKey)
        XCTAssertEqual(state.rows(Self.index).map(\.id), ["r0", "r1", "r2"])
    }

    func testTheIndexFiltersSearchesAndExportsWhatIsShown() {
        var state = DocIndexViewState()
        state.toggleFilter("Pleading")
        XCTAssertEqual(state.rows(Self.index).map(\.id), ["r0", "r2"])
        state.toggleFilter("Pleading")
        XCTAssertNil(state.filter)
        state.query = " NOTICE "
        XCTAssertEqual(state.rows(Self.index).map(\.id), ["r1"])
        XCTAssertEqual(state.showingLine(Self.index), "Showing 1 of 3 documents")
        state.toggleColumn("type", in: Self.index)
        XCTAssertEqual(state.csv(Self.index), "\u{FEFF}\"Document\",\"Pages\"\r\n\"Notice\",3\r\n")
        state.toggleColumn("doc", in: Self.index)
        state.toggleColumn("pp", in: Self.index)
        XCTAssertEqual(state.columns(Self.index).map(\.key), ["pp"], "the last column shown stays")
        XCTAssertEqual(Self.index.totals(shown: Self.index.rows).map(\.sum), [22])
    }

    func testAPickHiddenByTheChipsClearsThem() {
        let chart = DateChart.normalise(.object(["entries": .array([
            .object(["id": .string("a"), "day": .string("2020-01-01"), "cat": .string("ours"), "text": .string("Ours")]),
            .object(["id": .string("b"), "day": .string("2021-01-01"), "cat": .string("adverse"), "text": .string("Theirs")]),
        ])]))
        var state = DateChartViewState(category: .ours, query: "")
        XCTAssertEqual(state.countLine(chart), "1 of 2")
        XCTAssertFalse(state.reveal("a", in: chart))
        XCTAssertTrue(state.reveal("b", in: chart))
        XCTAssertNil(state.category)
        XCTAssertEqual(DateChartViewState.year(of: "b", in: chart), "2021")
        XCTAssertEqual(DateChartViewState.count(nil, in: chart), 2)
        XCTAssertEqual(DateChartViewState.count(.adverse, in: chart), 1)
    }
}
