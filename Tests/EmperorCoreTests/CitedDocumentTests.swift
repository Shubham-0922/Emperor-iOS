import XCTest
@testable import EmperorCore

/// Opening a reference to one of the reader's documents from a conversation, and finding its
/// quoted words in the viewer.
final class CitedDocumentTests: XCTestCase {

    private static let quote = "the lessee shall pay the monthly rent on the fifth day"
    private static var ref: DocumentReference {
        DocumentReference(file: "Lease_Agreement.pdf", page: 2, quote: quote)
    }

    // MARK: - From the conversation

    func testAFoundDocumentOpensAtTheServersPageWithTheQuote() async {
        await withChat { fake, _, model in
            fake.files["Lease_Agreement.pdf"] = resolvedFile(
                "Lease_Agreement.pdf", folder: "Bakshi", page: 3, status: "verified")
            await model.showCitedDocument(Self.ref)

            XCTAssertEqual(fake.resolves, [.init(name: "Lease_Agreement.pdf", quote: Self.quote, projectID: nil)])
            let source = model.openSource
            XCTAssertEqual(source?.attachment, ChatAttachment(name: "Lease_Agreement.pdf", folderName: "Bakshi"))
            XCTAssertEqual(source?.mention.startPage, 3, "the page the words were found on wins")
            XCTAssertEqual(source?.quote, Self.quote)
            XCTAssertEqual(source?.quoteStatus, .verified)
            XCTAssertNil(model.citationError)
        }
    }

    func testWithoutTheServersPageTheCitedPageIsUsed() async {
        await withChat { fake, _, model in
            fake.files["Lease_Agreement.pdf"] = resolvedFile("Lease_Agreement.pdf", page: nil, status: "unlocated")
            await model.showCitedDocument(Self.ref)
            XCTAssertEqual(model.openSource?.mention.startPage, 2)
            XCTAssertEqual(model.openSource?.quoteStatus, .unlocated)
        }
    }

    func testAMissingDocumentIsNamedAsTheWebNamesIt() async {
        await withChat { _, _, model in
            await model.showCitedDocument(Self.ref)
            XCTAssertNil(model.openSource)
            XCTAssertEqual(
                model.citationError,
                "“Lease_Agreement.pdf” is not among your documents, so it cannot be opened.")
        }
    }

    func testInAMattersConversationTheMatterIsAskedAndNamed() async {
        await withChat { fake, _, model in
            model.projectID = "12"
            await model.showCitedDocument(DocumentReference(file: "Notes.pdf", page: nil, quote: ""))
            XCTAssertEqual(fake.resolves, [.init(name: "Notes.pdf", quote: nil, projectID: "12")])
            XCTAssertEqual(
                model.citationError,
                "“Notes.pdf” is not among this matter’s documents, so it cannot be opened.")
        }
    }

    func testAFailedLookupSaysTheDocumentCouldNotBeOpened() async {
        await withChat { fake, _, model in
            fake.resolveError = APIError.server(status: 500, message: "boom")
            await model.showCitedDocument(Self.ref)
            XCTAssertNil(model.openSource)
            XCTAssertEqual(model.citationError, "The cited document could not be opened.")
        }
    }

    func testWithNoServerTheConversationsOwnDocumentsStillOpen() async {
        await withChat(resolver: false) { _, _, model in
            model.attachments = [ChatAttachment(name: "Lease_Agreement.pdf", folderName: "Bakshi")]
            await model.showCitedDocument(Self.ref)
            XCTAssertEqual(model.openSource?.attachment.folderName, "Bakshi")
            XCTAssertEqual(model.openSource?.quote, Self.quote)

            model.openSource = nil
            await model.showCitedDocument(DocumentReference(file: "Other.pdf", page: 1, quote: ""))
            XCTAssertEqual(model.citationError, "The cited document could not be opened.")
        }
    }

    /// A page mention the conversation and the library cannot place is asked of the server
    /// before it is called missing — a matter's file is not in the library listing.
    func testAMentionMissingFromTheLibraryIsAskedOfTheServer() async {
        await withChat { fake, files, model in
            model.projectID = "12"
            fake.files["Sale_Deed.pdf"] = resolvedFile("Sale_Deed.pdf", folder: "_projects/12")
            let mention = AnnexureMention(fileName: "Sale_Deed.pdf", mark: "P-3", startPage: 5, endPage: nil)
            await model.showSource(mention)

            XCTAssertEqual(files.treeCallCount, 1, "the library first")
            XCTAssertEqual(fake.resolves, [.init(name: "Sale_Deed.pdf", quote: nil, projectID: "12")])
            XCTAssertEqual(model.openSource?.attachment.folderName, "_projects/12")
            XCTAssertEqual(model.openSource?.mention, mention)
            XCTAssertNil(model.citationError)
        }
    }

    func testAMentionTheServerCannotFindKeepsItsWording() async {
        await withChat { _, _, model in
            await model.showSource(AnnexureMention(fileName: "Sale_Deed.pdf", mark: "", startPage: 5, endPage: nil))
            XCTAssertEqual(
                model.citationError,
                "Sale Deed.pdf is not in your document library any more, so its cited page cannot be opened.")
        }
    }

    // MARK: - In the viewer

    private static let pageText = (
        "The lessee shall pay the monthly rent on the fifth day of every calendar month to the "
            + "lessor at his registered office").split(separator: " ").map(String.init)

    func testTheQuoteIsFoundInThePagesOwnTextOnTheCitedPage() async {
        await withViewer { fake, model in
            let result = await model.findQuote(pageCount: 3) { $0 == 2 ? Self.pageText : ["nothing", "here"] }
            XCTAssertEqual(result, QuoteSearchResult(page: 2, target: 2, hit: .textWords(0...14)))
            XCTAssertNil(model.quoteNote)
            XCTAssertEqual(model.citedNote(page: 2), CitedNote(text: "The quoted words are highlighted.", isWarning: false))
            XCTAssertEqual(fake.pageRequests.map(\.page), [2])
            XCTAssertEqual(fake.pageRequests.first?.folder, "Bakshi")
        }
    }

    func testWordsThatCannotBeMarkedAreNotClaimedAsHighlighted() async {
        await withViewer { _, model in
            _ = await model.findQuote(pageCount: 3) { $0 == 2 ? Self.pageText : ["nothing", "here"] }
            model.quoteWasNotMarked()
            XCTAssertNotNil(model.quoteNote)
            XCTAssertEqual(model.citedNote(page: 2).isWarning, true)
        }
    }

    func testAScannedPagesPlacedWordsAreUsedWhenReady() async {
        await withViewer { fake, model in
            let boxes = Self.pageText.enumerated().map { i, w in
                (w, QuoteBox(x0: Double(i * 40), y0: 100, x1: Double(i * 40 + 35), y1: 112))
            }
            fake.pages[2] = PageWords(status: .ready, words: boxes)
            let result = await model.findQuote(pageCount: 3) { _ in [] }
            XCTAssertEqual(result?.hit, .scanBoxes([QuoteBox(x0: 0, y0: 100, x1: 595, y1: 112)]))
        }
    }

    func testWordsOnTheNextPageAreFoundAndSaidSo() async {
        await withViewer { _, model in
            let result = await model.findQuote(pageCount: 3) { $0 == 3 ? Self.pageText : ["other", "words"] }
            XCTAssertEqual(result?.page, 3)
            XCTAssertEqual(model.quoteNote, "The quoted words are on page 3; the citation said page 2.")
            XCTAssertEqual(
                model.citedNote(page: 3),
                CitedNote(text: "The quoted words are on page 3; the citation said page 2.", isWarning: true))
        }
    }

    func testAScanStillBeingPreparedIsSaid() async {
        await withViewer { fake, model in
            fake.pages[2] = PageWords(status: .pending)
            let result = await model.findQuote(pageCount: 3) { _ in ["scan"] }
            XCTAssertNil(result?.hit)
            XCTAssertEqual(result?.page, 2)
            XCTAssertEqual(
                model.quoteNote,
                "This scanned document is still being prepared for highlighting. Showing the cited page; try again in a minute or two.")
        }
    }

    func testWordsNotFoundAnywhereAreSaidSo() async {
        await withViewer { fake, model in
            fake.pageWordsError = APIError.transport("offline")
            _ = await model.findQuote(pageCount: 3) { _ in ["other", "words"] }
            XCTAssertEqual(model.quoteNote, "Couldn’t find the quoted words on page 2. Showing the cited page.")
            XCTAssertTrue(model.citedNote(page: 2).isWarning)
        }
    }

    func testNothingIsSearchedWithoutAQuoteOrInANonPDF() async {
        await withViewer(quote: "") { fake, model in
            let result = await model.findQuote(pageCount: 3) { _ in Self.pageText }
            XCTAssertNil(result)
            XCTAssertTrue(fake.pageRequests.isEmpty)
            XCTAssertEqual(model.citedNote(page: 2).text, "This is the page the answer cites.")
        }
        await withViewer(name: "Lease.docx") { fake, model in
            let result = await model.findQuote(pageCount: 3) { _ in Self.pageText }
            XCTAssertNil(result, "a Word document is shown converted, and searched for nothing")
            XCTAssertTrue(fake.pageRequests.isEmpty)
        }
    }

    func testTheHeadSaysWhatTheServerMadeOfTheQuote() async {
        let cases: [(QuoteStatus?, String?)] = [
            (.verified, "Quote checked"), (.mismatch, "Quote differs from the source"),
            (.unlocated, "Quote not found in the source"), (.tooShort, nil), (nil, nil),
        ]
        for (status, label) in cases {
            await withViewer(status: status) { _, model in
                XCTAssertEqual(model.quoteStatusLabel, label)
            }
        }
    }
}

@MainActor
private func withChat(
    resolver: Bool = true,
    _ body: @MainActor (FakeCitedSources, FakeFiles, ChatViewModel) async -> Void
) async {
    let fake = FakeCitedSources()
    let files = FakeFiles()
    let model = ChatViewModel(chatID: "chat-1", service: InertChat(), files: files)
    if resolver { model.citedSources = fake }
    await body(fake, files, model)
}

@MainActor
private func withViewer(
    name: String = "Lease_Agreement.pdf",
    quote: String = "the lessee shall pay the monthly rent on the fifth day of every calendar month",
    status: QuoteStatus? = nil,
    _ body: @MainActor (FakeCitedSources, SourceDocumentViewModel) async -> Void
) async {
    let fake = FakeCitedSources()
    let model = SourceDocumentViewModel(
        attachment: ChatAttachment(name: name, folderName: "Bakshi"),
        mention: AnnexureMention(fileName: name, mark: "", startPage: 2, endPage: nil),
        service: FakeFiles(), quote: quote, quoteStatus: status, words: fake)
    await body(fake, model)
}
