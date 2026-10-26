import XCTest
@testable import EmperorCore

/// The reading room, the judgment reader and the Act page, driven with `FakeLibrary`.
final class LibraryReaderTests: XCTestCase {

    private static func numberedJudgment(_ count: Int = 16) -> LibraryJudgment {
        var blocks = [JudgmentBlock(id: "b-0", kind: .cause, text: "A ... Appellant\nVersus\nB ... Respondent",
                                    lines: ["A ... Appellant", "Versus", "B ... Respondent"]),
                      JudgmentBlock(id: "h-1", kind: .heading, text: "JUDGMENT", level: 1)]
        for n in 1...count {
            blocks.append(JudgmentBlock(id: "para-\(n)", kind: .para, text: "The court considered point \(n).", n: String(n)))
        }
        var header = LibraryJudgmentHeader()
        header.petitioner = "Seethamma"
        header.respondent = "STATE OF KARNATAKA"
        header.court = "supremecourt"
        header.decidedOn = "2012-10-31"
        header.neutralCitation = "2012 INSC 410"
        header.citations = ["(2012) 10 SCC 409", "2012 INSC 410"]
        return LibraryJudgment(header: header, blocks: blocks,
                               toc: [JudgmentTOCEntry(id: "h-1", label: "JUDGMENT", level: 1)],
                               stats: JudgmentStats(paragraphs: count, words: 460, blocks: blocks.count))
    }

    // MARK: - Judgment reader

    func testFindCountsStepsAndWraps() async {
        await libraryRun { fake in
            fake.judgmentResult = .success(Self.numberedJudgment())
            let model = LibraryJudgmentViewModel(doc: .sample(257708, ext: ".txt"), service: fake)
            await model.load()
            XCTAssertEqual(model.state, .ready)
            XCTAssertFalse(model.isPlain)
            model.find("c")
            XCTAssertEqual(model.findLabel, "", "one character is not a search")
            model.find("COURT")
            XCTAssertEqual(model.hits.count, 16)
            XCTAssertEqual(model.findLabel, "1 of 16")
            XCTAssertEqual(model.currentHitBlockID, "para-1")
            model.step(-1)
            XCTAssertEqual(model.findLabel, "16 of 16", "back from the first wraps to the last")
            model.step(1)
            XCTAssertEqual(model.currentHitBlockID, "para-1")
            model.find("nowhere")
            XCTAssertEqual(model.findLabel, "No matches")
            model.step(1)
            XCTAssertNil(model.currentHitBlockID)
        }
    }

    func testContentsCarryParagraphMarksAndHeader() async {
        await libraryRun { fake in
            fake.judgmentResult = .success(Self.numberedJudgment())
            let model = LibraryJudgmentViewModel(doc: .sample(1, ext: ".txt"), service: fake)
            await model.load()
            XCTAssertEqual(model.contents.map(\.label), ["JUDGMENT", "Para 1", "Para 5", "Para 10", "Para 15"])
            XCTAssertEqual(model.paragraph("10").blockID, "para-10")
            XCTAssertEqual(model.paragraph("40").message, "There is no paragraph 40. The last is 16.")
            XCTAssertEqual(model.title, "Seethamma v. State of Karnataka")
            XCTAssertEqual(model.citations, ["2012 INSC 410", "(2012) 10 SCC 409"])
            XCTAssertEqual(model.citationLine, "Seethamma v. State of Karnataka, 2012 INSC 410 (Supreme Court, 31 Oct 2012)")
            XCTAssertEqual(model.lengthText, "16 paragraphs · 2 min read")
            XCTAssertEqual(model.paragraphLink("para-3", apiBaseURL: URL(string: "https://x.test/api")!).absoluteString,
                           "https://x.test/library/doc/1#para-3")
            model.enlarge()
            XCTAssertEqual(model.textScale, 1.08)
            for _ in 0..<10 { model.shrink() }
            XCTAssertEqual(model.textScale, 0.88)
        }
    }

    func testFallsBackToPlainTextButNotForAMissingFileOrASignOut() async {
        await libraryRun { fake in
            fake.judgmentResult = .failure(LibraryError.other("library_failed"))
            fake.fileResult = { _, prefer in
                XCTAssertEqual(prefer, "text")
                return Data("Title: X\n===\n1. First point.\n\n2. Second\npoint.".utf8)
            }
            let plain = LibraryJudgmentViewModel(doc: .sample(19655, ext: ".txt"), service: fake)
            await plain.load()
            XCTAssertEqual(plain.state, .ready)
            XCTAssertTrue(plain.isPlain)
            XCTAssertEqual(plain.blocks.map(\.text), ["First point.", "Second point."])
            XCTAssertEqual(plain.blocks.map(\.n), ["1", "2"])

            fake.judgmentResult = .failure(LibraryError.fileMissing)
            let missing = LibraryJudgmentViewModel(doc: .sample(2, ext: ".txt"), service: fake)
            await missing.load()
            XCTAssertEqual(missing.state, .missing)

            fake.judgmentResult = .failure(APIError.invalidCredentials)
            let signedOut = LibraryJudgmentViewModel(doc: .sample(3, ext: ".txt"), service: fake)
            await signedOut.load()
            XCTAssertEqual(signedOut.state, .failed(LoadFailure(APIError.invalidCredentials)))
            XCTAssertEqual(fake.fileCalls.count, 1, "only the first fell back to the text")
        }
    }

    func testPlainTextOverFourMegabytesIsRefused() async {
        await libraryRun { fake in
            fake.judgmentResult = .failure(LibraryError.tooLarge)
            fake.fileResult = { _, _ in Data(count: JudgmentText.maxReaderBytes + 1) }
            let model = LibraryJudgmentViewModel(doc: .sample(4, ext: ".txt"), service: fake)
            await model.load()
            XCTAssertEqual(model.state, .tooLarge)

            fake.judgmentResult = .failure(LibraryError.other("library_failed"))
            fake.fileResult = { _, _ in throw APIError.transport("offline") }
            let failed = LibraryJudgmentViewModel(doc: .sample(5, ext: ".txt"), service: fake)
            await failed.load()
            if case .failed(let f) = failed.state {
                XCTAssertEqual(f.message, LibraryError.other("library_failed").message, "the judgment's own failure is reported")
            } else {
                XCTFail("expected a failure, got \(failed.state)")
            }
        }
    }

    // MARK: - Reading room

    func testReadingRoomBranchesOnTheDocument() async {
        await libraryRun { fake in
            fake.judgmentResult = .success(Self.numberedJudgment(3))
            fake.docResult = { LibraryDocDetail(doc: .sample($0, ext: $0 == 257708 ? ".txt" : ".pdf")) }
            let text = LibraryReaderViewModel(seed: .sample(257708, ext: ".txt"), service: fake)
            await text.load()
            XCTAssertEqual(text.body, .judgment)
            XCTAssertEqual(text.judgment?.state, .ready)

            let pdf = LibraryReaderViewModel(seed: .sample(10), service: fake)
            await pdf.load()
            XCTAssertEqual(pdf.body, .pdf)
            XCTAssertEqual(pdf.file?.data, Data("%PDF-1.4".utf8))

            fake.docResult = { id in
                var d = LibraryDoc.sample(id)
                d.hasFile = false
                return LibraryDocDetail(doc: d)
            }
            let off = LibraryReaderViewModel(seed: .sample(999), service: fake)
            await off.load()
            XCTAssertEqual(off.file?.content, .missing)
            XCTAssertFalse(off.isOnShelf)

            fake.docResult = { _ in throw LibraryError.notFound }
            let gone = LibraryReaderViewModel(seed: .sample(998), service: fake)
            await gone.load()
            XCTAssertEqual(gone.body, .notFound)
        }
    }

    func testAFileIsAskedAboutBeforeItIsFetched() async {
        await libraryRun { fake in
            fake.headResult = { id in id == 999 ? (404, nil) : (200, LibraryFileViewModel.maxInMemoryBytes + 1) }
            let missing = LibraryFileViewModel(docID: 999, service: fake)
            await missing.load()
            XCTAssertEqual(missing.content, .missing)
            let huge = LibraryFileViewModel(docID: 5, service: fake)
            await huge.load()
            XCTAssertEqual(huge.content, .tooLarge(bytes: LibraryFileViewModel.maxInMemoryBytes + 1))
            XCTAssertEqual(fake.count("file"), 0, "neither was downloaded")
        }
    }

    // MARK: - Act page

    private static func bundle() -> LibraryActBundle {
        var act = LibraryDoc.sample(2478, "THE INDIAN PENAL CODE, 1860", category: "bare-acts")
        act.jurisdiction = "Central"
        act.aliases = ["IPC"]
        var rule1 = LibraryDoc.sample(2479, "Penal Rules, 1950", category: "bare-acts")
        rule1.year = 1950
        var rule2 = LibraryDoc.sample(2480, "Old Penal Rules (Rep., Act 5 of 1960)", category: "bare-acts")
        rule2.year = 1901
        var edition = LibraryDoc.sample(3001, "THE INDIAN PENAL CODE, 1860", category: "bare-acts")
        edition.jurisdiction = "Central"
        edition.fileSize = 2_000_000
        return LibraryActBundle(act: act, tabs: [
            LibraryActTab(key: "act", label: "The Act", count: 1, docs: [act]),
            LibraryActTab(key: "rules", label: "Rules", count: 2, docs: [rule1, rule2]),
            LibraryActTab(key: "amendments", label: "Amendments", count: 1, docs: [.sample(2481, "Amendment Act, 2013", category: "bare-acts")]),
            LibraryActTab(key: "editions", label: "Other editions", count: 1, docs: [edition]),
        ], selectedId: 2480, selectedTab: "rules")
    }

    func testActOpensOnTheTabAndInstrumentAskedFor() async {
        await libraryRun { fake in
            fake.actResult = .success(Self.bundle())
            let model = LibraryActViewModel(id: 2480, service: fake)
            await model.load()
            XCTAssertEqual(model.activeTab?.key, "rules")
            XCTAssertEqual(model.currentDoc?.id, 2480)
            XCTAssertEqual(model.tabs.first?.label, "The Code")
            XCTAssertEqual(model.kicker, ["Central Act", "1860", "IPC"])
            XCTAssertEqual(model.title, "The Indian Penal Code")
            XCTAssertEqual(model.holds, "2 rules · 1 amendment")
            let rules = try! XCTUnwrap(model.activeTab)
            XCTAssertEqual(model.latestID(in: rules), 2479)
            XCTAssertTrue(LibraryDisplay.isRepealed(rules.docs[1]))
            XCTAssertTrue(model.usesSegments)

            model.select(tab: "act")
            XCTAssertEqual(model.currentDoc?.id, 2478)
            XCTAssertEqual(model.choices(for: try! XCTUnwrap(model.activeTab)).map(\.id), [2478, 3001])
            XCTAssertEqual(LibraryActViewModel.editionLabel(model.editions[0], index: 0), "Edition 2 · India Code · 1.9 MB")
            model.select(doc: model.editions[0])
            XCTAssertEqual(model.currentDoc?.id, 3001)
            model.select(tab: "rules")
            XCTAssertEqual(model.currentDoc?.id, 2480, "each tab keeps its own instrument")
            XCTAssertTrue(model.file(for: rules.docs[0]) === model.file(for: rules.docs[0]))
        }
    }

    func testAnActKnownOnlyByItsAmendmentsIsOneChronology() async {
        await libraryRun { fake in
            var a = LibraryDoc.sample(1, "B Amendment Act, 2010", category: "bare-acts")
            a.year = 2010
            var b = LibraryDoc.sample(2, "A Amendment Act, 1990", category: "bare-acts")
            b.year = 1990
            fake.actResult = .success(LibraryActBundle(
                act: a, tabs: [LibraryActTab(key: "act", label: "x", count: 1, docs: [a]),
                               LibraryActTab(key: "amendments", label: "y", count: 1, docs: [b])],
                kind: "amendments"))
            let model = LibraryActViewModel(id: 1, service: fake)
            await model.load()
            XCTAssertEqual(model.tabs.map(\.key), ["amendments"])
            XCTAssertEqual(model.activeTab?.docs.map(\.id), [2, 1])
            XCTAssertEqual(model.holds, "2 amending Acts")
            XCTAssertEqual(model.notice, "The Act itself is not in the library")

            fake.actResult = .failure(LibraryError.notAnAct)
            let wrong = LibraryActViewModel(id: 9, service: fake)
            await wrong.load()
            XCTAssertEqual(wrong.failureTitle, "There is no such Act")
        }
    }
}
