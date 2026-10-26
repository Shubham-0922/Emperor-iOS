import XCTest
@testable import EmperorCore

final class FilingViewModelTests: XCTestCase {

    private static let start = Date(timeIntervalSince1970: 1_800_000_000)

    private static func standard() -> FakeFiling {
        let fake = FakeFiling()
        fake.draftList = [
            FilingDraft(id: "canvas_1", title: "Writ Petition — Look Out Circular", type: "doc",
                        createdAtRaw: "2026-10-01 09:00:00", chatID: "c1"),
            FilingDraft(id: "table_2", title: "List of dates", type: "table",
                        createdAtRaw: "2026-10-02T09:00:00.000Z", chatID: "c2"),
        ]
        fake.rows = [
            FilingAnnexure(id: 1, draftID: "canvas_1", mark: "P-1", title: "Board resolution",
                           sourceFilePath: "/storage/1/Bakshi/Plaint.pdf"),
            FilingAnnexure(id: 2, draftID: "canvas_1", mark: "P-2", title: "Notice",
                           sourceFilePath: "/storage/1/Notice.pdf", treatment: "typed",
                           verifyStatus: "pending"),
        ]
        return fake
    }

    private static let refusalError = APIError.classify(
        status: 402, body: Data(#"{"error":"Upgrade","code":"FEATURE_NOT_IN_PLAN"}"#.utf8))

    // MARK: - Drafts

    func testDraftsLoadAndFilterByTitle() async {
        await run { fake, model in
            await model.loadDrafts()
            XCTAssertEqual(model.draftsState, .loaded)
            XCTAssertEqual(model.drafts.count, 2)
            model.draftQuery = "  writ "
            XCTAssertEqual(model.filteredDrafts.map(\.id), ["canvas_1"])
            XCTAssertEqual(fake.count("drafts"), 1)
        }
    }

    func testAPlanRefusalReplacesThePage() async {
        await run { fake, model in
            fake.errors["*"] = Self.refusalError
            await model.loadDrafts()
            XCTAssertEqual(model.refusal?.code, .featureNotInPlan)
        }
    }

    func testPickReadsAnnexuresWithTheDraftsChat() async {
        await run { fake, model in
            await model.loadDrafts()
            await model.pick(model.drafts[0])
            XCTAssertEqual(model.annexures.map(\.mark), ["P-1", "P-2"])
            XCTAssertEqual(fake.annexureReads.first?.draftID, "canvas_1")
            XCTAssertEqual(fake.annexureReads.first?.chatID, "c1")
            XCTAssertEqual(model.annexState, .loaded)
            XCTAssertEqual(model.pendingTypedCount, 1)
            XCTAssertEqual(
                model.pendingTypedText,
                "1 typed copy not yet verified — assembly will proceed, but the checklist will flag it")
        }
    }

    func testChangeDraftClearsAnnexuresAndResult() async {
        await run { _, model in
            await model.loadDrafts()
            await model.pick(model.drafts[0])
            model.outcome = FilingAssemblyResult(success: true, pageCount: 3)
            model.changeDraft()
            XCTAssertNil(model.draft)
            XCTAssertTrue(model.annexures.isEmpty)
            XCTAssertNil(model.outcome)
        }
    }

    // MARK: - Annexure changes

    func testRenameIsShownAtOnceThenReadBack() async {
        await run { fake, model in
            await model.loadDrafts()
            await model.pick(model.drafts[0])
            // The read-back fails, so what is on screen is what was shown before the answer.
            fake.errors["annexures"] = APIError.server(status: 500, message: "down")
            await model.rename(model.annexures[0], to: "  Resolution of the Board ")
            XCTAssertEqual(fake.updates.first?.title, "Resolution of the Board")
            XCTAssertEqual(model.annexures[0].title, "Resolution of the Board")
            XCTAssertEqual(Array(fake.calls.suffix(2)), ["update", "annexures"])
        }
    }

    func testRenameToTheSameOrBlankTitleSendsNothing() async {
        await run { fake, model in
            await model.loadDrafts()
            await model.pick(model.drafts[0])
            await model.rename(model.annexures[0], to: " Board resolution ")
            await model.rename(model.annexures[0], to: "   ")
            XCTAssertTrue(fake.updates.isEmpty)
        }
    }

    func testTreatmentChangeSendsTheVerificationThePageSends() async {
        await run { fake, model in
            await model.loadDrafts()
            await model.pick(model.drafts[0])
            await model.setTreatment(model.annexures[0], .typed)
            XCTAssertEqual(fake.updates.last?.treatment, .typed)
            XCTAssertEqual(fake.updates.last?.verify, .pending)
            await model.setTreatment(model.annexures[1], .append)
            XCTAssertEqual(fake.updates.last?.verify, .notApplicable)
        }
    }

    func testVerifyingSaysSo() async {
        await run { fake, model in
            await model.loadDrafts()
            await model.pick(model.drafts[0])
            await model.toggleVerify(model.annexures[1])
            XCTAssertEqual(fake.updates.last?.verify, .verified)
            XCTAssertEqual(model.toast, "P-2 marked verified against the original")
            XCTAssertTrue(model.annexures[1].isVerified)
        }
    }

    func testAFailedChangeShowsTheServersWordsAndReloads() async {
        await run { fake, model in
            await model.loadDrafts()
            await model.pick(model.drafts[0])
            fake.errors["delete"] = APIError.server(status: 400, message: "annexure not found")
            await model.delete(model.annexures[0])
            XCTAssertEqual(model.notice, "annexure not found")
            XCTAssertEqual(model.annexures.count, 2, "the read-back restores the row")
        }
    }

    func testReorderIsOptimisticSendsThePermutationAndWarns() async {
        await run { fake, model in
            await model.loadDrafts()
            await model.pick(model.drafts[0])
            XCTAssertNil(model.orderWarning)
            await model.moveDown(model.annexures[0])
            XCTAssertEqual(fake.reorders, [[2, 1]])
            XCTAssertEqual(model.annexures.map(\.mark), ["P-2", "P-1"])
            XCTAssertEqual(
                model.orderWarning,
                "Annexure order no longer matches the mark sequence (P-1, P-2). Marks stay as assigned — the Index and List of Annexures will follow this binding order.")
            await model.moveUp(model.annexures[0])
            XCTAssertEqual(fake.reorders.count, 1, "the first row cannot move up")
        }
    }

    func testDragMovesRowsToTheirNewPlace() async {
        await run { fake, model in
            fake.rows.append(FilingAnnexure(id: 3, mark: "P-3", title: "Reply"))
            await model.loadDrafts()
            await model.pick(model.drafts[0])
            await model.move(fromOffsets: IndexSet(integer: 0), toOffset: 3)
            XCTAssertEqual(fake.reorders, [[2, 3, 1]])
        }
    }

    func testAddSendsTheFilesFolderAndReloads() async {
        await run { fake, model in
            await model.loadDrafts()
            await model.pick(model.drafts[0])
            let file = FileNode.StoredFile(name: "Engagement_Letter.pdf", path: "Engagement_Letter.pdf")
            let added = await model.add(file)
            XCTAssertTrue(added)
            XCTAssertEqual(fake.adds.first?.folderName, "")
            XCTAssertEqual(fake.adds.first?.fileName, "Engagement_Letter.pdf")
            XCTAssertEqual(model.annexures.last?.mark, "P-3")
            XCTAssertEqual(model.toast, "Added Engagement_Letter.pdf as an annexure")
        }
    }

    func testOnlyPDFsAreOfferedFromMyFiles() async {
        let files = FakeFiles()
        files.tree = [
            .folder(.init(name: "Bakshi", path: "Bakshi", files: [
                .file(.init(name: "Plaint.PDF", path: "Bakshi/Plaint.PDF")),
                .file(.init(name: "Note.docx", path: "Bakshi/Note.docx")),
            ])),
            .file(.init(name: "Letter.pdf", path: "Letter.pdf")),
        ]
        await filingModel(Self.standard(), files) { _, model in
            await model.loadFiles()
            XCTAssertEqual(model.pdfFiles.map(\.name), ["Plaint.PDF", "Letter.pdf"])
            model.fileQuery = "bakshi"
            XCTAssertEqual(model.filteredFiles.map(\.name), ["Plaint.PDF"])
        }
    }

    // MARK: - Assembly

    func testCanAssembleNeedsADraftAndASupportedForum() async {
        await run { _, model in
            await model.loadDrafts()
            XCTAssertFalse(model.canAssemble)
            XCTAssertNil(model.assembleHint)
            await model.pick(model.drafts[0])
            XCTAssertFalse(model.canAssemble)
            XCTAssertEqual(model.assembleHint, "Select the forum for the cover page")
            model.cover.forum = "Debts Recovery Tribunal (DRT)"
            XCTAssertFalse(model.canAssemble)
            XCTAssertEqual(
                model.assembleHint,
                "Assembly supports NCLT, NCLAT, High Court and Supreme Court covers")
            model.cover.forum = "High Court of Delhi"
            XCTAssertTrue(model.canAssemble)
            XCTAssertNil(model.assembleHint)
        }
    }

    func testAnUnsupportedForumIsNeverSent() async {
        await run { fake, model in
            await model.loadDrafts()
            await model.pick(model.drafts[0])
            model.cover.forum = "Arbitral Tribunal"
            await model.assemble()
            XCTAssertEqual(fake.count("assemble"), 0)
        }
    }

    func testAssembleRunsOnceAndShowsTheBundle() async {
        await run { fake, model in
            await model.loadDrafts()
            await model.pick(model.drafts[0])
            model.cover.forum = "NCLT"
            await model.assemble()
            XCTAssertEqual(fake.count("assemble"), 1)
            XCTAssertEqual(model.outcome?.success, true)
            XCTAssertEqual(model.toast, "Bundle assembled — 42 pages")
            XCTAssertFalse(model.isAssembling)
        }
    }

    func testAFailedAssemblyListsEveryProblem() async {
        await run { fake, model in
            fake.assembleAnswer = FilingAssemblyResult(
                success: false, errors: [.string("P-1: source file missing")])
            await model.loadDrafts()
            await model.pick(model.drafts[0])
            model.cover.forum = "NCLT"
            await model.assemble()
            XCTAssertEqual(model.outcome?.errorLines, ["P-1: source file missing"])
            XCTAssertEqual(fake.count("assemble"), 1)
        }
    }

    func testALostAnswerAdoptsTheBundleMadeSinceTheTap() async {
        await run { fake, model in
            fake.bundleList = [FilingBundle(
                id: 5, draftID: "canvas_1", pageCount: 30, status: "ok",
                createdAt: Int(Self.start.timeIntervalSince1970 * 1000) - 60_000)]
            fake.bundlesMadeByAssemble = [FilingBundle(
                id: 6, draftID: "canvas_1", pageCount: 44, status: "ok",
                createdAt: Int(Self.start.timeIntervalSince1970 * 1000) + 90_000)]
            fake.errors["assemble"] = APIError.transport("The request timed out.")
            await model.loadDrafts()
            await model.pick(model.drafts[0])
            model.cover.forum = "Supreme Court"
            await model.assemble()
            XCTAssertEqual(fake.count("assemble"), 1, "never retried")
            XCTAssertEqual(model.outcome?.success, true)
            XCTAssertEqual(model.outcome?.bundleId, 6)
            XCTAssertEqual(model.outcome?.successTitle, "Bundle assembled — 44 pages")
        }
    }

    func testALostAnswerWithNoNewBundleIsAFailure() async {
        await run { fake, model in
            fake.bundleList = [FilingBundle(
                id: 5, draftID: "canvas_1", pageCount: 30, status: "ok",
                createdAt: Int(Self.start.timeIntervalSince1970 * 1000) - 60_000)]
            fake.errors["assemble"] = APIError.transport("The request timed out.")
            await model.loadDrafts()
            await model.pick(model.drafts[0])
            model.cover.forum = "NCLT"
            await model.assemble()
            XCTAssertEqual(model.outcome?.success, false)
            XCTAssertEqual(
                model.outcome?.errorLines,
                [DisplayText.message(for: APIError.transport("The request timed out."))])
        }
    }

    func testARefusedAssemblyShowsTheRefusal() async {
        await run { fake, model in
            await model.loadDrafts()
            await model.pick(model.drafts[0])
            fake.errors["assemble"] = Self.refusalError
            model.cover.forum = "NCLT"
            await model.assemble()
            XCTAssertEqual(model.refusal?.code, .featureNotInPlan)
            XCTAssertNil(model.outcome)
        }
    }

    func testTheChecklistIsAskedOnlyForAForumTheAssemblerReads() async {
        await run { fake, model in
            await model.loadDrafts()
            await model.pick(model.drafts[0])
            XCTAssertEqual(fake.count("checklist"), 0)
            model.cover.forum = "DRT"
            await model.refreshChecklist()
            XCTAssertEqual(fake.count("checklist"), 0)
            model.cover.forum = "hc"
            await model.refreshChecklist()
            XCTAssertEqual(fake.count("checklist"), 1)
            XCTAssertNotNil(model.checklist)
        }
    }

    func testRemovePromptIsThePagesQuestion() {
        let a = FilingAnnexure(id: 1, mark: "P-1", title: "Board resolution")
        XCTAssertEqual(
            FilingAssemblyViewModel.removePrompt(for: a),
            "Remove annexure P-1 — “Board resolution”? Its mark will not be reused.")
    }

    // MARK: - Harness

    private func run(_ body: @MainActor (FakeFiling, FilingAssemblyViewModel) async -> Void) async {
        await filingModel(Self.standard(), FakeFiles(), body)
    }
}

@MainActor
private func filingModel(
    _ fake: FakeFiling, _ files: FakeFiles,
    _ body: @MainActor (FakeFiling, FilingAssemblyViewModel) async -> Void
) async {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    await body(fake, FilingAssemblyViewModel(service: fake, files: files, now: { start }))
}
