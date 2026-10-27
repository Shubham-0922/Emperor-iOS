import XCTest
@testable import EmperorCore

/// Editing a saved draft and saving it over its row.
final class DraftEditorTests: XCTestCase {

    private static let row = DraftedItem(
        id: "d1", chatID: "c1", title: "Plaint", type: "doc",
        createdAtRaw: "2026-10-01 09:00:00", chatTitle: "Bakshi")

    func testUnchangedTextSendsNothing() async {
        await editing { fake, model in
            model.beginEditing()
            let saved = await model.save("<p>Draft</p>")
            XCTAssertFalse(saved)
            XCTAssertTrue(fake.saves.isEmpty)
            XCTAssertEqual(model.phase, .reading)
        }
    }

    func testBlankHTMLIsRefused() async {
        await editing { fake, model in
            model.beginEditing()
            let saved = await model.save("<h1> </h1><p>&nbsp;</p>")
            XCTAssertFalse(saved)
            XCTAssertTrue(fake.saves.isEmpty)
            XCTAssertEqual(model.phase, .failed(DraftEditor.emptyMessage))
            XCTAssertEqual(model.content, "<p>Draft</p>")
        }
    }

    func testSaveSendsTheRowsIdKindAndConversation() async {
        await editing { fake, model in
            model.beginEditing()
            let saved = await model.save("<p>Edited</p>")
            XCTAssertTrue(saved)
            XCTAssertEqual(fake.saves, [FakeFileRoutes.Save(
                id: "d1", title: "Plaint", content: "<p>Edited</p>", type: "doc", chatId: "c1")])
            XCTAssertEqual(model.content, "<p>Edited</p>")
            XCTAssertEqual(model.phase, .reading)
        }
    }

    func testARowWithoutKindOrConversationSendsADocAndNoChat() {
        let row = DraftedItem(id: "d2", chatID: "", title: nil, type: nil)
        let request = DraftEditorModel.request(item: row, content: "x")
        XCTAssertEqual(request.type, "doc")
        XCTAssertNil(request.chatId)
        XCTAssertEqual(request.title, "Untitled")
        XCTAssertEqual(request.id, "d2")
    }

    func testAnotherReturnedIdIsAdoptedForTheNextSave() async {
        await editing { fake, model in
            fake.saveResult = SaveDocumentResult(
                success: true, id: "d7", type: "doc", deduped: true, reclassified: false, error: nil)
            model.beginEditing()
            _ = await model.save("<p>One</p>")
            XCTAssertEqual(model.itemID, "d7")
            XCTAssertEqual(model.currentItem.id, "d7")
            XCTAssertEqual(model.currentItem.chatID, "c1")

            fake.saveResult = SaveDocumentResult(
                success: true, id: nil, type: "doc", deduped: false, reclassified: false, error: nil)
            model.beginEditing()
            _ = await model.save("<p>Two</p>")
            XCTAssertEqual(fake.saves.last?.id, "d7")
        }
    }

    func testARefusalKeepsTheEdit() async {
        await editing { fake, model in
            fake.saveError = APIError.server(status: 403, message: "That draft is not yours.")
            model.beginEditing()
            let saved = await model.save("<p>Edited</p>")
            XCTAssertFalse(saved)
            XCTAssertEqual(model.phase, .failed("That draft is not yours."))
            XCTAssertEqual(model.errorMessage, "That draft is not yours.")
            XCTAssertEqual(model.pendingEdit, "<p>Edited</p>")
            XCTAssertEqual(model.content, "<p>Draft</p>")
            XCTAssertTrue(model.isEditing)

            model.cancel()
            XCTAssertEqual(model.phase, .reading)
            XCTAssertNil(model.pendingEdit)
        }
    }

    func testHistoryReplacesTheOpenedDraftWithoutChangingWhichReaderItIs() async {
        await history { model in
            await model.load()
            await model.runOpen(Self.row)
            let before = model.opened?.id
            model.replaceOpened(content: "<p>New</p>", id: "d7")
            XCTAssertEqual(model.opened?.id, before)
            XCTAssertEqual(model.opened?.item.id, "d7")
            XCTAssertEqual(model.opened?.content, "<p>New</p>")
            XCTAssertEqual(model.items.map(\.id), ["d7", "d2"])
        }
    }

    func testArtifactPageCanBeEditable() {
        XCTAssertTrue(ArtifactDocument.html(wrapping: "<p>x</p>", editable: true)
            .contains(#"<div class="scroll" contenteditable="true"><p>x</p></div>"#))
        XCTAssertTrue(ArtifactDocument.html(wrapping: "<p>x</p>")
            .contains(#"<div class="scroll"><p>x</p></div>"#))
    }

    // MARK: - Helpers

    private func editing(_ body: @MainActor (FakeFileRoutes, DraftEditorModel) async -> Void) async {
        await draftEditor(Self.row, body)
    }

    private func history(_ body: @MainActor (DraftHistoryViewModel) async -> Void) async {
        await draftHistory([Self.row, DraftedItem(id: "d2", title: "Reply")], body)
    }
}

@MainActor
private func draftEditor(
    _ row: DraftedItem, _ body: @MainActor (FakeFileRoutes, DraftEditorModel) async -> Void
) async {
    let fake = FakeFileRoutes()
    await body(fake, DraftEditorModel(item: row, content: "<p>Draft</p>", service: fake))
}

private final class ListedDrafts: DraftHistoryProviding, @unchecked Sendable {
    let rows: [DraftedItem]
    init(_ rows: [DraftedItem]) { self.rows = rows }
    func drafts(_ kind: DraftKind) async throws -> [DraftedItem] { rows }
    func content(id: String) async throws -> String { "<p>Draft</p>" }
}

@MainActor
private func draftHistory(
    _ rows: [DraftedItem], _ body: @MainActor (DraftHistoryViewModel) async -> Void
) async {
    await body(DraftHistoryViewModel(service: ListedDrafts(rows)))
}
