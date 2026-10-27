import XCTest
@testable import EmperorCore

/// Filing Assembly opened on a conversation's draft: its annexures by the conversation alone, its
/// files one tap from being annexures, no reordering, the cover read once from the cause title,
/// and assembly sending the draft as it stands.
final class FilingChatScopeTests: XCTestCase {

    private static let draftHTML =
        "<p>IN THE HIGH COURT OF DELHI AT NEW DELHI</p><p>W.P.(C) No. 1234/2024</p>"
        + "<p>Anil Kumar Goel v. Union of India</p>"
        + "<p>Annexure P-1: Board resolution <@Plaint.pdf:P-1:2-4> is filed.</p>"

    private static let context = FilingChatContext(
        chatID: "c1", draftTitle: "Writ Petition", draftHTML: draftHTML,
        attachments: [
            ChatAttachment(name: "Plaint.pdf", folderName: "Bakshi"),
            ChatAttachment(name: "Reply.pdf", folderName: "Bakshi"),
            ChatAttachment(name: "Root.pdf"),
        ])

    private static func fake() -> FakeFiling {
        let fake = FakeFiling()
        fake.rows = [
            FilingAnnexure(id: 11, chatID: "c1", mark: "P-1", title: "Board resolution",
                           sourceFilePath: "/storage/1/Bakshi/Plaint.pdf"),
            FilingAnnexure(id: 12, chatID: "c1", mark: "P-2", title: "Notice",
                           sourceFilePath: "/storage/1/Notice.pdf", treatment: "typed",
                           verifyStatus: "pending"),
        ]
        return fake
    }

    // MARK: - The conversation's files

    func testTheConversationsFilesAreListedOnceEachByFolderAndName() {
        func message(_ role: MessageRole, _ files: [JSONValue]?) -> ChatMessage {
            var m = ChatMessage(role: role, content: "text")
            m.attachments = files
            return m
        }
        let messages = [
            message(.user, [
                .object(["name": .string("EVIDENCE.pdf"), "folderName": .string("Vijay")]),
                .string("Root.pdf"),
            ]),
            message(.assistant, nil),
            message(.user, [
                .object(["name": .string("EVIDENCE.pdf"), "folderName": .string("Anil")]),
                .object(["name": .string("EVIDENCE.pdf"), "folderName": .string("Vijay")]),
            ]),
        ]
        let files = FilingChatScope.attachments(in: messages)
        XCTAssertEqual(files.map(\.name), ["EVIDENCE.pdf", "Root.pdf", "EVIDENCE.pdf"])
        XCTAssertEqual(files.map(\.folderName), ["Vijay", nil, "Anil"])
    }

    func testOnlyADocumentInAStoredConversationIsFiled() {
        let doc = StreamArtifact(kind: .canvas, format: .markdown, title: "Writ", body: "# Writ\n\nBody [1]")
        let table = StreamArtifact(kind: .table, format: .markdown, title: "Dates", body: "| a |\n|---|\n| b |")
        let files = [ChatAttachment(name: "A.pdf")]
        let context = FilingChatScope.context(for: doc, chatID: "c1", attachments: files)
        XCTAssertEqual(context?.chatID, "c1")
        XCTAssertEqual(context?.draftTitle, "Writ")
        XCTAssertEqual(context?.attachments, files)
        XCTAssertTrue(context?.draftHTML.contains("<h1") ?? false, "markdown goes as HTML")
        XCTAssertFalse(context?.draftHTML.contains("[1]") ?? true, "a filing carries no citations")
        XCTAssertNil(FilingChatScope.context(for: table, chatID: "c1", attachments: files))
        XCTAssertNil(FilingChatScope.context(for: doc, chatID: nil, attachments: files))
        XCTAssertNil(FilingChatScope.context(for: doc, chatID: "", attachments: files))
    }

    func testTheLeadNamesTheDraft() {
        XCTAssertEqual(
            FilingChatScope.lead(for: "Writ Petition"),
            "Assembling Writ Petition and its annexures into a court-ready, paginated bundle with cover, index and list of annexures.")
        XCTAssertTrue(FilingChatScope.lead(for: "  ").hasPrefix("Assembling this draft and"))
    }

    func testASavedDraftBecomesAFilingDraft() {
        let item = DraftedItem(
            id: "canvas_9", chatID: "c4", title: "Reply", type: "doc",
            createdAtRaw: "2026-10-01 09:00:00", chatTitle: "Kapoor")
        let draft = FilingDraft(item)
        XCTAssertEqual(draft.id, "canvas_9")
        XCTAssertEqual(draft.chatID, "c4")
        XCTAssertEqual(draft.type, "doc")
    }

    // MARK: - The screen in a conversation's scope

    func testStartReadsTheConversationsAnnexuresAndBundlesOnly() async {
        await chatModel(Self.fake()) { fake, model in
            XCTAssertNotNil(model.draft)
            XCTAssertEqual(model.annexuresStep, 1)
            XCTAssertEqual(model.coverStep, 2)
            await model.start()
            XCTAssertEqual(fake.count("drafts"), 0)
            XCTAssertEqual(fake.annexureReads.first?.draftID, nil)
            XCTAssertEqual(fake.annexureReads.first?.chatID, "c1")
            XCTAssertEqual(model.annexures.map(\.mark), ["P-1", "P-2"])
            XCTAssertEqual(fake.count("bundles"), 1)
            XCTAssertEqual(model.draft?.id, "chat:c1")
        }
    }

    func testAFileAlreadyAnAnnexureIsNotOffered() async {
        await chatModel(Self.fake()) { _, model in
            await model.start()
            XCTAssertEqual(model.seedFiles.map(\.name), ["Reply.pdf", "Root.pdf"])
        }
    }

    func testASeedIsAddedToTheConversationWithItsFolder() async {
        await chatModel(Self.fake()) { fake, model in
            await model.start()
            let added = await model.addSeed(ChatAttachment(name: "Reply.pdf", folderName: "Bakshi"))
            XCTAssertTrue(added)
            XCTAssertEqual(fake.chatAdds.first?.chatID, "c1")
            XCTAssertEqual(fake.chatAdds.first?.folderName, "Bakshi")
            XCTAssertEqual(fake.chatAdds.first?.fileName, "Reply.pdf")
            XCTAssertEqual(model.toast, "Added Reply.pdf as an annexure")
            XCTAssertEqual(model.annexures.map(\.mark), ["P-1", "P-2", "P-3"])
            XCTAssertFalse(model.seedFiles.contains { $0.name == "Reply.pdf" })
        }
    }

    func testAFileFromMyFilesIsAddedToTheConversation() async {
        await chatModel(Self.fake()) { fake, model in
            await model.start()
            let file = FileNode.StoredFile(name: "Order.pdf", path: "Orders/Order.pdf")
            _ = await model.add(file)
            XCTAssertEqual(fake.chatAdds.map(\.fileName), ["Order.pdf"])
            XCTAssertTrue(fake.adds.isEmpty)
        }
    }

    func testAConversationsAnnexuresAreNotReordered() async {
        await chatModel(Self.fake()) { fake, model in
            await model.start()
            XCTAssertFalse(model.canReorder)
            await model.moveDown(model.annexures[0])
            await model.move(fromOffsets: IndexSet(integer: 1), toOffset: 0)
            XCTAssertEqual(fake.count("reorder"), 0)
            XCTAssertEqual(model.annexures.map(\.mark), ["P-1", "P-2"])
        }
    }

    func testTheCoverIsReadOnceFromTheCauseTitle() async {
        await chatModel(Self.fake()) { _, model in
            XCTAssertEqual(model.cover.forum, "HIGH COURT")
            XCTAssertEqual(model.cover.caseNumber, "W.P.(C) No. 1234/2024")
            XCTAssertEqual(model.cover.caseType, "W.P.(C)")
            // The page reads on past the respondent, as it does; the golden test holds it to that.
            XCTAssertEqual(model.cover.parties, "Anil Kumar Goel versus Union of India Annexure P-1")
            model.cover.forum = "Supreme Court"
            model.cover.parties = ""
            model.deriveCover()
            XCTAssertEqual(model.cover.forum, "Supreme Court")
            XCTAssertEqual(model.cover.parties, "", "read again after it was read once")
        }
    }

    func testATypedFieldIsNeverOverwritten() async {
        let context = FilingChatContext(
            chatID: "c1", draftTitle: "Writ", draftHTML: "<p>Nothing to read</p>", attachments: [])
        await chatModel(Self.fake(), context: context) { _, model in
            XCTAssertEqual(model.cover, FilingCover())
            model.cover.forum = "NCLT"
            model.deriveCover()
            XCTAssertEqual(model.cover.forum, "NCLT")
        }
    }

    func testAssemblySendsTheDraftWithoutItsMentions() async {
        await chatModel(Self.fake()) { fake, model in
            await model.start()
            model.cover.forum = "High Court"
            await model.assemble()
            XCTAssertEqual(fake.count("chatAssemble"), 1)
            XCTAssertEqual(fake.count("assemble"), 0)
            let sent = fake.chatAssembles.first
            XCTAssertEqual(sent?.chatID, "c1")
            XCTAssertEqual(sent?.title, "Writ Petition")
            XCTAssertFalse(sent?.html.contains("<@") ?? true)
            XCTAssertTrue(sent?.html.contains("Board resolution  is filed.") ?? false)
            XCTAssertEqual(model.outcome?.success, true)
        }
    }

    func testALostAnswerIsReconciledAgainstTheConversationsBundles() async {
        let fake = Self.fake()
        fake.errors["chatAssemble"] = APIError.transport("The network connection was lost.")
        fake.bundlesMadeByAssemble = [
            FilingBundle(id: 9, draftID: "chat:c1", pageCount: 30, status: "ok", createdAt: 1_800_000_010_000),
        ]
        await chatModel(fake) { _, model in
            await model.start()
            model.cover.forum = "NCLT"
            await model.assemble()
            XCTAssertEqual(model.outcome?.bundleId, 9)
            XCTAssertEqual(model.outcome?.success, true)
        }
    }

    func testNoChecklistIsAskedForAConversation() async {
        await chatModel(Self.fake()) { fake, model in
            await model.start()
            model.cover.forum = "NCLT"
            await model.refreshChecklist()
            XCTAssertEqual(fake.count("checklist"), 0)
            XCTAssertNil(model.checklist)
        }
    }

    func testThereIsNoGoingBackToADraftList() async {
        await chatModel(Self.fake()) { _, model in
            model.changeDraft()
            XCTAssertNotNil(model.draft)
        }
    }

    func testASavedDraftScopeOpensOnThatDraft() async {
        let fake = Self.fake()
        let draft = FilingDraft(id: "canvas_1", title: "Writ", type: "doc", createdAtRaw: nil, chatID: "c1")
        await scopedModel(fake, scope: .draft(draft)) { fake, model in
            await model.start()
            XCTAssertEqual(fake.count("drafts"), 0)
            XCTAssertEqual(model.draft?.id, "canvas_1")
            XCTAssertEqual(fake.annexureReads.first?.draftID, "canvas_1")
            XCTAssertEqual(fake.annexureReads.first?.chatID, "c1")
            XCTAssertTrue(model.canReorder)
            XCTAssertTrue(model.seedFiles.isEmpty)
        }
    }

    // MARK: - Cards and the viewer

    func testCardsSayTheFormAndARepeatedFile() async {
        let fake = Self.fake()
        fake.rows.append(FilingAnnexure(id: 13, chatID: "c1", mark: "P-3", title: "Order", duplicateOf: "P-1"))
        await viewing(fake) { fake in
            let cards = FilingAnnexureCardsModel(service: fake, chatID: "c1")
            await cards.load()
            XCTAssertTrue(cards.hasLoaded)
            XCTAssertEqual(cards.rows.map(\.cardForm), ["original", "typed copy", "original"])
            XCTAssertEqual(cards.rows.map(\.duplicateNote), [nil, nil, "same file as P-1"])
            XCTAssertEqual(cards.rows[1].viewerTitle, "Annexure P-2 — Notice")
            XCTAssertEqual(fake.annexureReads.first?.draftID, nil)

            fake.errors["annexures"] = APIError.transport("offline")
            await cards.load()
            XCTAssertTrue(cards.rows.isEmpty, "an unreadable register shows no list")
        }
    }

    func testTheViewerShowsATypedCopyOrWhyThereIsNone() async {
        let fake = Self.fake()
        await viewing(fake) { fake in
            let typed = fake.rows[1]
            let model = FilingAnnexureViewerModel(service: fake, chatID: "c1", annexure: typed)
            await model.load()
            XCTAssertEqual(model.content, .typed("<p>typed</p>"))

            fake.typedCopyAnswer = FilingTypedCopy(html: nil, skipped: true, reason: "")
            await model.load()
            XCTAssertEqual(model.content, .message(FilingAnnexureViewerModel.couldNotLoad))

            fake.errors["typedCopy"] = APIError.server(status: 400, message: "no OCR text for P-2")
            await model.load()
            XCTAssertEqual(model.content, .message("no OCR text for P-2"))
        }
    }

    func testTheViewerShowsAnOriginalByItsKind() async {
        let fake = Self.fake()
        fake.originalAnswers = [
            "P-1": FilingOriginal(data: Data("%PDF-1.4".utf8), mime: "application/pdf"),
        ]
        await viewing(fake) { fake in
            let original = fake.rows[0]
            let model = FilingAnnexureViewerModel(service: fake, chatID: "c1", annexure: original)
            await model.load()
            XCTAssertEqual(model.content, .pdf(Data("%PDF-1.4".utf8)))

            fake.originalAnswers["P-1"] = FilingOriginal(data: Data([1]), mime: "image/webp")
            await model.load()
            XCTAssertEqual(model.content, .image(Data([1])))

            fake.errors["original"] = FilingPreviewError.unpreviewable
            await model.load()
            XCTAssertEqual(model.content, .unpreviewable)

            fake.errors["original"] = APIError.transport("offline")
            await model.load()
            XCTAssertEqual(model.content, .message(FilingAnnexureViewerModel.couldNotLoad))
        }
    }

    // MARK: - Harness

    private func chatModel(
        _ fake: FakeFiling, context: FilingChatContext = FilingChatScopeTests.context,
        _ body: @MainActor (FakeFiling, FilingAssemblyViewModel) async -> Void
    ) async {
        await scopedModel(fake, scope: .chat(context), body)
    }
}

@MainActor
private func viewing(_ fake: FakeFiling, _ body: @MainActor (FakeFiling) async -> Void) async {
    await body(fake)
}

@MainActor
private func scopedModel(
    _ fake: FakeFiling, scope: FilingScope,
    _ body: @MainActor (FakeFiling, FilingAssemblyViewModel) async -> Void
) async {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let model = FilingAssemblyViewModel(service: fake, files: FakeFiles(), scope: scope, now: { start })
    await body(fake, model)
}
