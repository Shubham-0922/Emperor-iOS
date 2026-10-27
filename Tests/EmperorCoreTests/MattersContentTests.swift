import XCTest
@testable import EmperorCore

/// A matter's content: its conversations' titles, its files (folders, staging, writes, the
/// reading followed), attach from My Files, the chronology read out of its documents, and keeping
/// a case as a matter. Driven on the main actor through a free function — see `ChatViewModelTests`.
final class MattersContentTests: XCTestCase {

    // MARK: - Ask

    func testPlaceholderTitlesReadAsNewConversation() {
        for raw in [nil, "", "  ", "New chat", "AI Chat", "untitled", "Untitled Session", "untitled conversation"] {
            XCTAssertEqual(MatterChatsViewModel.title(for: raw), "New conversation", "\(raw ?? "nil")")
        }
        XCTAssertEqual(MatterChatsViewModel.title(for: " Draft the rejoinder "), "Draft the rejoinder")
        XCTAssertEqual(MatterChatsViewModel.title(for: "New chat about bail"), "New chat about bail")
    }

    func testConversationsAreNewestFirstByUpdateThenLinkTime() {
        let model = MatterChatsViewModel(chats: [
            ProjectChat(id: "old", title: "Old", updatedAtRaw: "2026-01-01 10:00:00"),
            ProjectChat(id: "linked", title: nil, updatedAtRaw: nil, linkedAtRaw: "2026-06-01 10:00:00"),
            ProjectChat(id: "new", title: "New one", updatedAtRaw: "2026-10-01T10:00:00.000Z"),
        ])
        XCTAssertEqual(model.rows.map(\.id), ["new", "linked", "old"])
        XCTAssertEqual(model.rows[1].title, "New conversation")
        XCTAssertEqual(model.latestID, "new")
        XCTAssertFalse(model.rows[0].when.isEmpty)
    }

    // MARK: - Files

    private static func writListing() -> MatterFiles {
        let root = "_projects/prj-writ"
        return MatterFiles(root: root, folders: [
            matterFolderNode("\(root)/Pleadings", [
                matterFileNode("\(root)/Pleadings/Petition.pdf", modified: "2026-10-01T09:00:00.000Z"),
                matterFileNode("\(root)/Pleadings/Reply.pdf", status: "Reading page 2 of 9", modified: "2026-10-02T09:00:00.000Z"),
            ]),
            matterFolderNode("\(root)/Zeta notes"),
            matterFolderNode("\(root)/Alpha", [matterFolderNode("\(root)/Alpha/Inner", [
                matterFileNode("\(root)/Alpha/Inner/Scan.pdf", status: "scanned"),
            ])]),
            matterFolderNode("\(root)/Receipts", [matterFileNode("\(root)/Receipts/Challan.pdf", status: "ERROR: unreadable")]),
        ], files: [matterFileNode("\(root)/Loose.docx")])
    }

    func testStandardFoldersComeFirstInTheirOrderThenTheUsersThenUnfiled() async {
        await onMain {
            let service = FakeMatterFiles()
            service.listings = [Self.writListing()]
            let model = MatterFilesViewModel(projectID: "prj-writ", service: service)
            await model.load()
            XCTAssertEqual(model.folders.map(\.name),
                           ["Pleadings", "Orders", "Evidence", "Correspondence", "Receipts", "Alpha", "Zeta notes", "Unfiled"])
            let pleadings = model.folders[0]
            XCTAssertEqual(pleadings.count, 2)
            XCTAssertFalse(model.canRename(pleadings), "a standard folder cannot be renamed")
            XCTAssertFalse(model.canDelete(model.folders.last!), "the matter's root cannot be deleted")
            XCTAssertTrue(model.canDelete(model.folders[5]))
            XCTAssertEqual(model.folders[5].count, 1, "a sub-folder's files count towards its top folder")
            XCTAssertEqual(model.openFiles.map(\.name), ["Reply.pdf", "Petition.pdf"], "newest first")
            XCTAssertEqual(model.openFiles[0].statusText, "Being read")
            XCTAssertEqual(model.destinations.prefix(5), ["Pleadings", "Orders", "Evidence", "Correspondence", "Receipts"])
            XCTAssertTrue(model.destinations.contains("Alpha/Inner"))
        }
    }

    func testOnlyReadyAndScannedFilesAreStaged() async {
        await onMain {
            let service = FakeMatterFiles()
            service.listings = [Self.writListing()]
            let model = MatterFilesViewModel(projectID: "prj-writ", service: service)
            await model.load()
            XCTAssertEqual(Set(model.readyFiles.map(\.name)), ["Petition.pdf", "Scan.pdf", "Loose.docx"])
            let petition = model.readyFiles.first { $0.name == "Petition.pdf" }
            XCTAssertEqual(petition?.folderName, "_projects/prj-writ/Pleadings", "the folder is the server's address")
        }
    }

    func testTheReadingIsFollowedUntilItEnds() async {
        await onMain {
            let root = "_projects/p"
            let reading = MatterFiles(root: root, folders: [], files: [matterFileNode("\(root)/A.pdf", status: "Queued")])
            let done = MatterFiles(root: root, folders: [], files: [matterFileNode("\(root)/A.pdf")])
            let service = FakeMatterFiles()
            service.listings = [reading, reading, done]
            let model = MatterFilesViewModel(projectID: "p", service: service)
            await model.load()
            XCTAssertTrue(model.isProcessing)
            let waits = WaitLog()
            await model.followReading(sleep: { waits.add($0) })
            XCTAssertFalse(model.isProcessing)
            XCTAssertEqual(waits.all, [1.5, 3])
            XCTAssertEqual(service.listingCalls, 3)
        }
    }

    func testTheReadingIsNotFollowedForever() async {
        await onMain {
            let root = "_projects/p"
            let service = FakeMatterFiles()
            service.listings = [MatterFiles(root: root, folders: [], files: [matterFileNode("\(root)/A.pdf", status: "Queued")])]
            let model = MatterFilesViewModel(projectID: "p", service: service)
            await model.load()
            let waits = WaitLog()
            await model.followReading(sleep: { waits.add($0) })
            XCTAssertEqual(waits.all.reduce(0, +), MatterFilesViewModel.pollLimit, accuracy: 10)
            XCTAssertEqual(waits.all.last, 10)
        }
    }

    func testRenameAndDeleteGoThroughTheFileRoutesByTheMattersFolder() async {
        await onMain {
            let service = FakeMatterFiles()
            service.listings = [Self.writListing()]
            let files = FakeFileManaging()
            let model = MatterFilesViewModel(projectID: "prj-writ", service: service, files: files)
            await model.load()
            let petition = model.allFiles.first { $0.name == "Petition.pdf" }!
            _ = await model.delete(petition)
            let alpha = model.folders.first { $0.name == "Alpha" }!
            _ = await model.deleteFolder(alpha)
            _ = await model.deleteFolder(model.folders[0])
            XCTAssertEqual(files.calls, [
                "delete _projects/prj-writ/Pleadings/Petition.pdf",
                "deleteFolder _projects/prj-writ/Alpha",
            ], "a standard folder is never deleted")
            XCTAssertEqual(model.message, "Deleted the folder Alpha")
            XCTAssertEqual(MatterFilesViewModel.deleteFolderMessage(count: 1),
                           "1 document in it will be permanently deleted from this matter, with the text and search index built from it.")
            XCTAssertEqual(MatterFilesViewModel.deleteFolderMessage(count: 0), "The folder is empty.")
        }
    }

    func testANewFolderOpens() async {
        await onMain {
            let service = FakeMatterFiles()
            service.folderAnswer = ("_projects/p/Written statement", false)
            let model = MatterFilesViewModel(projectID: "p", service: service)
            let blank = await model.createFolder("  ")
            XCTAssertFalse(blank)
            XCTAssertEqual(model.error, "Folder name is required")
            let made = await model.createFolder(" Written statement ")
            XCTAssertTrue(made)
            XCTAssertEqual(service.folders, ["Written statement"])
            XCTAssertEqual(model.current, "Written statement")
            XCTAssertEqual(model.message, "Folder “Written statement” created")
        }
    }

    // MARK: - Drafts

    func testAMattersDraftsAreBothKindsNewestFirstAndAHalfThatFailsIsSaid() async {
        await onMain {
            let drafts = FakeMatterDrafts()
            drafts.documents = [
                DraftedItem(id: "d1", title: "Notice", type: "doc", createdAtRaw: "2026-10-01T10:00:00.000Z", projectID: "p"),
                DraftedItem(id: "d2", title: "Rejoinder", type: "doc", createdAtRaw: "2026-10-03 10:00:00", projectID: "p"),
            ]
            drafts.tables = [DraftedItem(id: "t1", title: "Dates", type: "table", createdAtRaw: "2026-10-02T10:00:00.000Z", projectID: "p")]
            let model = MatterDraftListViewModel(projectID: "p", service: drafts)
            await model.load()
            XCTAssertEqual(model.items.map(\.id), ["d2", "t1", "d1"])
            XCTAssertEqual(drafts.asked, ["doc p", "table p"])
            XCTAssertTrue(model.isTable(model.items[1]))
            await model.open(model.items[0])
            XCTAssertEqual(model.opened?.content, "<h1>d2</h1>")

            drafts.tablesError = APIError.server(status: 500, message: "x")
            await model.load()
            XCTAssertEqual(model.partial, "Tables could not be loaded.")
            XCTAssertEqual(model.items.map(\.id), ["d2", "d1"])

            drafts.documentsError = APIError.server(status: 500, message: "Down")
            let failing = MatterDraftListViewModel(projectID: "p", service: drafts)
            await failing.load()
            XCTAssertNotNil(failing.state.failure)
        }
    }

    // MARK: - Attach from My Files

    private static func myFiles() -> FakeFiles {
        let files = FakeFiles()
        files.tree = [
            matterFolderNode("Bakshi", [
                matterFileNode("Bakshi/Plaint.pdf"),
                matterFileNode("Bakshi/Draft.pdf", status: "Reading page 1 of 3"),
            ]),
            matterFolderNode("_projects", [matterFolderNode("_projects/p", [matterFileNode("_projects/p/X.pdf")])]),
            matterFileNode("Engagement.pdf", status: "scanned"),
        ]
        return files
    }

    func testOnlyFinishedMyFilesDocumentsCanBeTickedAndMattersStorageIsNeverOffered() async {
        await onMain {
            let model = AttachFromMyFilesViewModel(projectID: "p", myFiles: Self.myFiles(), service: FakeMatterFiles())
            await model.load()
            XCTAssertEqual(model.groups.map(\.title), ["My Files", "Bakshi"])
            XCTAssertFalse(model.groups.flatMap(\.rows).contains { $0.file.name == "X.pdf" })
            let draft = model.groups[1].rows.first { $0.file.name == "Draft.pdf" }!
            XCTAssertFalse(model.selectable(draft))
            XCTAssertEqual(draft.whyNot, "Still being read in My Files. It can be attached once it is ready.")
            model.toggle(draft)
            XCTAssertTrue(model.selected.isEmpty)
            XCTAssertEqual(model.readingNote, "1 document is still being read in My Files. They can be attached once they are ready.")
            model.query = "plaint"
            XCTAssertEqual(model.groups.flatMap(\.rows).map(\.file.name), ["Plaint.pdf"])
        }
    }

    func testNoMoreThanTwentyFiveAtATime() async {
        await onMain {
            let files = FakeFiles()
            files.tree = (1...26).map { matterFileNode("Doc\($0).pdf") }
            let model = AttachFromMyFilesViewModel(projectID: "p", myFiles: files, service: FakeMatterFiles())
            await model.load()
            for row in model.groups.flatMap(\.rows) { model.toggle(row) }
            XCTAssertEqual(model.selected.count, 25)
            XCTAssertEqual(model.notice, "Up to 25 documents at a time. Attach these, then pick the rest.")
        }
    }

    func testAttachingSaysEachOutcomeAndKeepsTheSkippedTicked() async {
        await onMain {
            let service = FakeMatterFiles()
            service.attachResult = AttachResult(folder: "_projects/p/Orders", rows: [
                AttachRow(name: "Plaint.pdf", status: "indexing", source: MatterFileRef(folderName: "Bakshi", fileName: "Plaint.pdf")),
                AttachRow(name: "Engagement.pdf", status: "skipped", source: MatterFileRef(folderName: "", fileName: "Engagement.pdf"),
                          reason: "Already in this matter (Pleadings/Engagement.pdf)", already: true),
            ])
            let model = AttachFromMyFilesViewModel(
                projectID: "p", myFiles: Self.myFiles(), service: service, destinations: ["Pleadings", "Orders"], destination: "Orders")
            await model.load()
            for row in model.groups.flatMap(\.rows) { model.toggle(row) }
            XCTAssertEqual(model.attachTitle, "Attach 2 documents")
            let summary = await model.attach()
            XCTAssertEqual(summary, "1 attached · 1 skipped: Already in this matter (Pleadings/Engagement.pdf)")
            XCTAssertEqual(service.attached.first?.subfolder, "Orders")
            XCTAssertEqual(Set(service.attached.first?.files ?? []), [
                MatterFileRef(folderName: "Bakshi", fileName: "Plaint.pdf"),
                MatterFileRef(folderName: "", fileName: "Engagement.pdf"),
            ])
            XCTAssertEqual(model.selected, [MatterFileRef(folderName: "", fileName: "Engagement.pdf")])
            XCTAssertEqual(model.skipped.map(\.sourceName), ["Engagement.pdf"])
            XCTAssertFalse(model.finished)
        }
    }

    func testARefusedAttachSaysWhyAndKeepsTheSelection() async {
        await onMain {
            let service = FakeMatterFiles()
            service.attachError = APIError.server(status: 413, message: "These documents come to more than 2048 MB. Attach them in smaller groups.")
            let model = AttachFromMyFilesViewModel(projectID: "p", myFiles: Self.myFiles(), service: service)
            await model.load()
            model.toggle(model.groups[0].rows[0])
            let summary = await model.attach()
            XCTAssertNil(summary)
            XCTAssertEqual(model.error, "These documents come to more than 2048 MB. Attach them in smaller groups.")
            XCTAssertEqual(model.selected.count, 1)
        }
    }

    // MARK: - Build from documents

    private static let existing = [
        MatterRecord.Entry(key: "u1", id: "u1", src: .manual, own: true, kind: "filing", day: "2025-03-01",
                           title: "Writ petition filed before the High Court", body: "", sourceRef: "", created: "", item: nil),
    ]

    func testProposalsReadTheDateDayFirstFallBackToEventAndStartDuplicatesUnticked() {
        let proposals = ChronologyExtractViewModel.proposals([
            ExtractedEvent(date: "01-03-2025", title: "Writ petition filed", details: "Filed in person", kind: "filing", sourceRef: "Petition.pdf, p. 1"),
            ExtractedEvent(date: "2025-02-30", title: "Notice served", kind: "notice"),
            ExtractedEvent(date: "05.01.2024", title: "  Agreement signed  ", kind: "milestone"),
            ExtractedEvent(date: "2024-01-05", title: "", kind: "order"),
        ], existing: Self.existing)
        XCTAssertEqual(proposals.map(\.day), ["2025-03-01", "", "2024-01-05", "2024-01-05"])
        XCTAssertTrue(proposals[0].dup, "contained in an entry already on the record, on the same day")
        XCTAssertFalse(proposals[0].on)
        XCTAssertTrue(proposals[1].undated)
        XCTAssertFalse(proposals[1].on)
        XCTAssertEqual(proposals[1].kind, "event", "an unknown kind is an event")
        XCTAssertEqual(proposals[1].rawDate, "2025-02-30")
        XCTAssertEqual(proposals[2].title, "Agreement signed")
        XCTAssertTrue(proposals[2].on)
        XCTAssertFalse(proposals[3].on, "an untitled proposal cannot be saved")
        XCTAssertEqual(ChronologyExtractViewModel.norm("  Writ—Petition, FILED! "), "writ petition filed")
        XCTAssertFalse(ChronologyExtractViewModel.sameEvent("short", "short one"), "containment needs twelve characters")
    }

    func testTickedProposalsAreSavedOneByOneAsAIEntries() async {
        await onMain {
            let service = FakeMatterFiles()
            service.proposals = ChronologyProposalSet(events: [
                ExtractedEvent(date: "2025-04-10", title: "Notice issued", details: "Reply in four weeks", kind: "order", sourceRef: "Order.pdf, p. 2"),
                ExtractedEvent(date: "2025-05-01", title: "Reply filed", kind: "filing"),
                ExtractedEvent(date: "2025-06-01", title: "Rejoinder", kind: "filing"),
            ], files: 2, partial: true)
            let writes = FakeProjectWrites()
            let model = ChronologyExtractViewModel(projectID: "prj-writ", service: service, writes: writes, existing: [])
            await model.start()
            XCTAssertEqual(model.phase, .review)
            XCTAssertTrue(model.partial)
            XCTAssertNil(service.extracted.first!, "all documents: no file list")
            model.toggle(2)
            XCTAssertEqual(model.saveTitle, "Add 2 to the chronology")
            let added = await model.accept()
            XCTAssertTrue(added)
            XCTAssertEqual(writes.calls, ["saveUpdate", "saveUpdate"])
            let first = writes.bodies["saveUpdate"]![0]
            XCTAssertEqual(first["source"], .string("ai"))
            XCTAssertEqual(first["kind"], .string("order"))
            XCTAssertEqual(first["eventDate"], .string("2025-04-10"))
            XCTAssertEqual(first["body"], .string("Reply in four weeks"))
            XCTAssertEqual(first["sourceRef"], .string("Order.pdf, p. 2"))
            XCTAssertEqual(first["projectId"], .string("prj-writ"))
            XCTAssertNil(writes.bodies["saveUpdate"]![1]["sourceRef"])
            XCTAssertEqual(model.result, "2 events added to the chronology")
        }
    }

    func testAFailedSaveIsCounted() {
        XCTAssertEqual(ChronologyExtractViewModel.resultMessage(added: 1, failed: 2, lastError: "Pick the date."),
                       "1 added; 2 could not be saved — Pick the date..")
        XCTAssertEqual(ChronologyExtractViewModel.resultMessage(added: 1, failed: 0, lastError: ""), "1 event added to the chronology")
    }

    func testChosenDocumentsAreSentAndOnlyReadyOnesCanBeChosen() async {
        await onMain {
            let service = FakeMatterFiles()
            service.listings = [Self.writListing()]
            let model = ChronologyExtractViewModel(projectID: "prj-writ", service: service, writes: FakeProjectWrites(), existing: [])
            await model.chooseSome()
            XCTAssertFalse(model.canStart)
            for file in model.files ?? [] { model.toggleFile(file) }
            XCTAssertEqual(model.chosen.count, 3, "a file still being read or unreadable cannot be chosen")
            await model.start()
            let sent = service.extracted.first.flatMap { $0 } ?? []
            XCTAssertEqual(Set(sent.map(\.fileName)), ["Petition.pdf", "Scan.pdf", "Loose.docx"])
            XCTAssertTrue(sent.contains(MatterFileRef(folderName: "_projects/prj-writ", fileName: "Loose.docx")))
        }
    }

    func testClosingAbandonsARead() async {
        await onMain {
            let service = FakeMatterFiles()
            service.proposals = ChronologyProposalSet(events: [ExtractedEvent(date: "2025-01-01", title: "X")])
            let model = ChronologyExtractViewModel(projectID: "p", service: service, writes: FakeProjectWrites(), existing: [])
            service.onExtract = { await MainActor.run { model.abandon() } }
            await model.start()
            XCTAssertEqual(model.phase, .reading)
            XCTAssertTrue(model.proposals.isEmpty)
        }
    }

    func testAFailedReadSaysWhy() async {
        await onMain {
            let service = FakeMatterFiles()
            service.extractError = APIError.server(status: 503, message: "No AI provider is configured")
            let model = ChronologyExtractViewModel(projectID: "p", service: service, writes: FakeProjectWrites(), existing: [])
            await model.start()
            XCTAssertEqual(model.phase, .failed)
            XCTAssertEqual(model.error, "No AI provider is configured")
        }
    }

    // MARK: - Keeping a case as a matter

    private static let pick = CourtSearchResult(
        courtType: "hc", courtCode: "PHHC", courtName: "Punjab and Haryana High Court", caseType: "RFA",
        caseNumber: "12", caseYear: "2025", cnr: "PHHC010000122025", title: "ANKIT BHALLA VS STATE OF HARYANA")

    private static func tracked(_ id: String) -> LegalCase {
        var c = LegalCase(id: id)
        c.cnr = "PHHC010000122025"
        c.caseNumber = "12"
        c.caseYear = "2025"
        c.caseType = "RFA"
        c.courtCode = "PHHC"
        return c
    }

    func testAnAlreadyTrackedCaseIsNotSavedAgainAndTheSideIsPatched() async {
        let cases = FakeCases()
        cases.cases = [Self.tracked("case-x")]
        let search = FakeTrackingSearch()
        let writes = FakeProjectWrites()
        let service = MatterCreationService(
            tracking: CaseTracking(cases: cases, search: search), writes: writes, projects: FakeProjects())
        let request = AddToMattersRequest(
            pick: Self.pick, caseTitle: nil, name: "  ", side: .second, firstLead: "ANKIT BHALLA", secondLead: "STATE OF HARYANA")
        let result = await service.addToMatters(request)
        XCTAssertEqual(try? result.get(), MatterCreated(projectID: "prj-from-case-x", existed: false))
        XCTAssertTrue(search.saved.isEmpty)
        XCTAssertEqual(writes.fromCase.first?.caseID, "case-x")
        XCTAssertEqual(writes.fromCase.first?.name, "Ankit Bhalla v. State of Haryana", "a blank name is the case's title")
        XCTAssertNil(writes.fromCase.first?.banner)
        let fields = writes.patched.first?.fields.json
        XCTAssertEqual(fields?["ourSide"], .string("respondent"), "an appeal's second side is the respondent")
        XCTAssertEqual(fields?["client"], .string("State of Haryana"))
        XCTAssertEqual(fields?["oppositeParty"], .string("Ankit Bhalla"))
    }

    func testANewCaseIsSavedAndNoSideMeansNoPatch() async {
        let search = FakeTrackingSearch()
        search.outcome = .saved(id: "case-new")
        let writes = FakeProjectWrites()
        writes.existed = true
        let service = MatterCreationService(
            tracking: CaseTracking(cases: FakeCases(), search: search), writes: writes, projects: FakeProjects())
        let result = await service.addToMatters(AddToMattersRequest(pick: Self.pick, name: "Bhalla appeal"))
        XCTAssertEqual(try? result.get(), MatterCreated(projectID: "prj-from-case-new", existed: true))
        XCTAssertEqual(try? result.get().toast, "Opened your existing matter for this case")
        XCTAssertEqual(search.saved.count, 1)
        XCTAssertEqual(writes.fromCase.first?.name, "Bhalla appeal")
        XCTAssertTrue(writes.patched.isEmpty)
    }

    func testAlreadySavedIsLookedUpAgain() async {
        let cases = FakeCases()
        let search = FakeTrackingSearch()
        search.outcome = .alreadySaved(message: "This case is already on the team dashboard")
        search.onSave = { cases.cases = [Self.tracked("case-found")] }
        let writes = FakeProjectWrites()
        let service = MatterCreationService(
            tracking: CaseTracking(cases: cases, search: search), writes: writes, projects: FakeProjects())
        _ = await service.addToMatters(AddToMattersRequest(pick: Self.pick))
        XCTAssertEqual(writes.fromCase.first?.caseID, "case-found")
    }

    func testAMatterThatCouldNotBeMadeSaysSo() async {
        let search = FakeTrackingSearch()
        let writes = FakeProjectWrites()
        writes.saveError = APIError.server(status: 500, message: "Database is locked")
        let service = MatterCreationService(
            tracking: CaseTracking(cases: FakeCases(), search: search), writes: writes, projects: FakeProjects())
        let result = await service.addToMatters(AddToMattersRequest(pick: Self.pick))
        guard case .failure(let failure) = result else { return XCTFail("expected a failure") }
        XCTAssertEqual(failure.message, "Database is locked")
    }

    func testTheExistingMatterForACaseIsFoundAmongArchivedOnesToo() async {
        let cases = FakeCases()
        cases.cases = [Self.tracked("case-x")]
        let projects = FakeProjects()
        projects.list = [Project(id: "prj-other", linkedCaseID: "case-y"), Project(id: "prj-old", linkedCaseID: "case-x")]
        let service = MatterCreationService(
            tracking: CaseTracking(cases: cases, search: FakeTrackingSearch()), writes: FakeProjectWrites(), projects: projects)
        let found = await service.existingMatter(for: Self.pick)
        XCTAssertEqual(found, "prj-old")
        XCTAssertEqual(projects.archivedRequests, [true])
        XCTAssertEqual(CaseToMatter.matterID(forCase: "case-y", in: projects.list), "prj-other")
        XCTAssertNil(CaseToMatter.matterID(forCase: "", in: projects.list))
    }

    func testCaseToMatterFailuresAreWordedAsTheWebWordsThem() async {
        let writes = FakeProjectWrites()
        let service = MatterCreationService(
            tracking: CaseTracking(cases: FakeCases(), search: FakeTrackingSearch()), writes: writes, projects: FakeProjects())

        writes.saveError = APIError.server(status: 404, message: "Case not found")
        let missing = await service.openCaseAsMatter(caseID: "case-x")
        XCTAssertEqual(missing, .failure(.notFound))
        XCTAssertEqual(CaseToMatterFailure.notFound.title, "Case not found")

        writes.saveError = APIError.server(status: 403, message: "You are not a member of the team that tracks that case")
        let shared = await service.openCaseAsMatter(caseID: "case-x")
        guard case .failure(let forbidden) = shared else { return XCTFail("expected a refusal") }
        XCTAssertEqual(forbidden.message, "You are not a member of the team that tracks that case. Ask whoever tracks it to add you to their team.")
        XCTAssertFalse(forbidden.canRetry)

        writes.saveError = APIError.server(status: 500, message: "Something broke")
        let other = await service.openCaseAsMatter(caseID: "case-x")
        XCTAssertEqual(other, .failure(.other("Something broke")))
        XCTAssertTrue(CaseToMatterFailure.other("").canRetry)
        XCTAssertEqual(CaseToMatterFailure.other("").message, "The server did not answer.")

        writes.saveError = nil
        writes.existed = true
        let opened = await service.openCaseAsMatter(caseID: "case-x")
        XCTAssertEqual(opened, .success(MatterCreated(projectID: "prj-from-case-x", existed: true)))
        XCTAssertEqual(writes.fromCase.last?.name, nil)
    }

    func testTheAddToMattersSheetOffersTheSidesInTheCasesOwnWords() async {
        await onMain {
            let fake = FakeMatterCreation()
            let model = AddToMattersViewModel(
                request: AddToMattersRequest(pick: Self.pick, firstLead: "ANKIT BHALLA", secondLead: nil), service: fake)
            XCTAssertEqual(model.request.name, "Ankit Bhalla v. State of Haryana")
            XCTAssertEqual(model.optionTitle(.first), "I act for the appellant side")
            XCTAssertEqual(model.optionTitle(.second), "I act for the respondent side")
            XCTAssertEqual(model.optionDetail(.first), "Ankit Bhalla")
            XCTAssertNil(model.optionDetail(.second))
            model.request.name = " "
            XCTAssertFalse(model.canAdd)
            model.request.name = "Bhalla"
            fake.added = .failure(MatterRuleError(message: "The case could not be added to your tracked cases."))
            let made = await model.add()
            XCTAssertNil(made)
            XCTAssertEqual(model.error, "The case could not be added to your tracked cases.")
        }
    }

    func testOpenAsMatterKeepsTheFailure() async {
        await onMain {
            let fake = FakeMatterCreation()
            fake.opened = .failure(.notFound)
            let model = CaseToMatterViewModel(caseID: "case-sc", service: fake)
            let first = await model.open()
            XCTAssertNil(first)
            XCTAssertEqual(model.failure, .notFound)
            fake.opened = .success(MatterCreated(projectID: "prj-9", existed: false))
            let second = await model.open()
            XCTAssertEqual(second?.projectID, "prj-9")
            XCTAssertNil(model.failure)
            XCTAssertEqual(fake.openedCases, ["case-sc", "case-sc"])
        }
    }
}

/// The waits a poll asked for, in order.
final class WaitLog: @unchecked Sendable {
    private let lock = NSLock()
    private var waits: [TimeInterval] = []
    func add(_ t: TimeInterval) { lock.withLock { waits.append(t) } }
    var all: [TimeInterval] { lock.withLock { waits } }
}

@MainActor
private func onMain(_ body: @MainActor () async -> Void) async {
    await body()
}
