import XCTest
@testable import EmperorCore

final class CloudImportModelTests: XCTestCase {

    private static let files = [
        CloudFile(id: "f1", name: "a.pdf", mime: "application/pdf", size: 2048),
        CloudFile(id: "f2", name: "b.docx", mime: nil, size: nil),
        CloudFile(id: "f3", name: "Notes.txt", mime: "text/plain", size: 10),
    ]

    // MARK: - Which drive

    func testDefaultProviderRule() {
        XCTAssertEqual(CloudImportModel.defaultProvider([.google: .on(), .microsoft: .on()]), .google)
        XCTAssertEqual(CloudImportModel.defaultProvider([.google: .ready, .microsoft: .on()]), .microsoft)
        XCTAssertEqual(CloudImportModel.defaultProvider([.google: .ready, .microsoft: .ready]), .google)
        XCTAssertEqual(CloudImportModel.defaultProvider([:]), .google)
    }

    // MARK: - Load

    func testNothingConfiguredSaysSoon() async {
        let fake = FakeCloudDrive([.google: .off, .microsoft: .off])
        await cloudImport(fake) { model in
            await model.load()
            XCTAssertEqual(model.blocker, CloudCopy.soon)
            XCTAssertTrue(fake.listed.isEmpty)
            XCTAssertEqual(model.state, .loaded)
        }
    }

    func testNotConnectedSaysWhereToConnectWithoutListing() async {
        let fake = FakeCloudDrive([.google: .ready, .microsoft: .off])
        await cloudImport(fake) { model in
            await model.load()
            XCTAssertEqual(model.provider, .google)
            XCTAssertEqual(
                model.blocker, "Google Drive is not connected — connect it in Account → Connected services")
            XCTAssertTrue(fake.listed.isEmpty)
        }
    }

    func testListsTheConnectedDrive() async {
        let fake = FakeCloudDrive([.google: .ready, .microsoft: .on()])
        fake.filesValue = Self.files
        await cloudImport(fake) { model in
            await model.load()
            XCTAssertEqual(model.provider, .microsoft)
            XCTAssertEqual(model.title, "Import from OneDrive")
            XCTAssertEqual(fake.listed, [.microsoft])
            XCTAssertEqual(model.files.count, 3)
            XCTAssertNil(model.blocker)
            XCTAssertFalse(model.showsProviderPicker)
        }
    }

    func testAccessProblemIsABlockerWithTheServersWords() async {
        let fake = FakeCloudDrive([.google: .on()])
        fake.listError = APIError.server(status: 409, message: "Google Drive session expired — please reconnect in Account → Connected services")
        await cloudImport(fake) { model in
            await model.load()
            XCTAssertEqual(model.blocker, "Google Drive session expired — please reconnect in Account → Connected services")
            XCTAssertNil(model.state.failure)
        }
    }

    func testOfflineIsAFailureToRetry() async {
        let fake = FakeCloudDrive([.google: .on()])
        fake.listError = APIError.transport("The Internet connection appears to be offline.")
        await cloudImport(fake) { model in
            await model.load()
            XCTAssertNotNil(model.state.failure)
            XCTAssertNil(model.blocker)
        }
    }

    func testBothConnectedOffersTheChoiceAndSwitching() async {
        let fake = FakeCloudDrive([.google: .on(), .microsoft: .on()])
        fake.filesValue = Self.files
        await cloudImport(fake) { model in
            await model.load()
            XCTAssertTrue(model.showsProviderPicker)
            model.toggle(Self.files[0])
            await model.choose(.microsoft)
            XCTAssertEqual(fake.listed, [.google, .microsoft])
            XCTAssertTrue(model.selection.isEmpty, "a choice in one drive does not carry to another")
        }
    }

    func testSearchFiltersLocally() async {
        let fake = FakeCloudDrive([.google: .on()])
        fake.filesValue = Self.files
        await cloudImport(fake) { model in
            await model.load()
            model.query = " NOTES "
            XCTAssertEqual(model.visibleFiles.map(\.id), ["f3"])
            model.query = ""
            XCTAssertEqual(model.visibleFiles.count, 3)
        }
    }

    // MARK: - Run

    func testRunImportsInOrderIntoTheFolder() async {
        let fake = FakeCloudDrive([.google: .on()])
        fake.filesValue = Self.files
        await cloudImport(fake, destination: "Bakshi") { model in
            await model.load()
            model.toggle(Self.files[1])
            model.toggle(Self.files[0])
            XCTAssertEqual(model.importTitle, "Import 2")
            let summary = await model.run()
            XCTAssertEqual(fake.imported.map(\.id), ["f1", "f2"])
            XCTAssertEqual(fake.imported.map(\.folder), ["Bakshi", "Bakshi"])
            XCTAssertEqual(summary.imported, 2)
            XCTAssertEqual(summary.toast, "Imported 2 files — making them searchable now")
            XCTAssertNil(summary.firstFailure)
            XCTAssertFalse(model.isImporting)
        }
    }

    func testTopLevelIsNil() async {
        let fake = FakeCloudDrive([.google: .on()])
        fake.filesValue = Self.files
        await cloudImport(fake, destination: "") { model in
            await model.load()
            XCTAssertNil(model.destination)
            model.toggle(Self.files[0])
            let summary = await model.run()
            XCTAssertNil(fake.imported.first?.folder)
            XCTAssertEqual(summary.toast, "Imported 1 file — making them searchable now")
        }
    }

    func testOrdinaryFailureContinuesAndIsNamed() async {
        let fake = FakeCloudDrive([.google: .on()])
        fake.filesValue = Self.files
        fake.importErrors["f1"] = APIError.server(status: 400, message: "That file type cannot be imported")
        await cloudImport(fake) { model in
            await model.load()
            Self.files.forEach { model.toggle($0) }
            let summary = await model.run()
            XCTAssertEqual(fake.imported.map(\.id), ["f2", "f3"])
            XCTAssertEqual(summary.imported, 2)
            XCTAssertEqual(summary.firstFailure, "a.pdf: That file type cannot be imported")
            XCTAssertNil(summary.refusal)
            XCTAssertEqual(model.selection, ["f1"], "what did not arrive stays chosen")
        }
    }

    func testRefusalStopsTheRun() async {
        let fake = FakeCloudDrive([.google: .on()])
        fake.filesValue = Self.files
        let body = Data(#"{"success":false,"error":"Upgrade to upload more","code":"DOCUMENT_LIMIT"}"#.utf8)
        fake.importErrors["f2"] = APIError.classify(status: 402, body: body)
        await cloudImport(fake) { model in
            await model.load()
            Self.files.forEach { model.toggle($0) }
            let summary = await model.run()
            XCTAssertEqual(fake.imported.map(\.id), ["f1"], "nothing is tried after a refusal")
            XCTAssertEqual(summary.imported, 1)
            XCTAssertEqual(summary.refusal?.code, .documentLimit)
            XCTAssertEqual(summary.failures.count, 1)
            XCTAssertFalse(summary.failures[0].contains("Upgrade"), "a plan refusal is worded by the app")
        }
    }

    func testNothingChosenDoesNothing() async {
        let fake = FakeCloudDrive([.google: .on()])
        fake.filesValue = Self.files
        await cloudImport(fake) { model in
            await model.load()
            XCTAssertFalse(model.canImport)
            XCTAssertEqual(model.importTitle, "Import")
            let summary = await model.run()
            XCTAssertEqual(summary, CloudImportSummary())
            XCTAssertNil(summary.toast)
        }
    }

    // MARK: - Export

    func testExportLocationSplitsThePath() {
        XCTAssertTrue(CloudExportModel.location(ofPath: "Bakshi/Orders/x.pdf") == ("Bakshi/Orders", "x.pdf"))
        XCTAssertTrue(CloudExportModel.location(ofPath: "Loose.pdf") == (nil, "Loose.pdf"))
    }

    func testExportSaysWhereAndCarriesTheLink() async {
        let fake = FakeCloudDrive([.google: .on()])
        await cloudExport(fake) { model in
            await model.export(path: "Bakshi/Plaint.pdf", to: .google)
            XCTAssertEqual(fake.exported.first?.name, "Plaint.pdf")
            XCTAssertEqual(fake.exported.first?.folder, "Bakshi")
            XCTAssertEqual(model.exported?.message, "Plaint.pdf saved to Google Drive")
            XCTAssertEqual(model.exported?.url?.host, "drive.google.com")
        }
    }

    func testExportFailureIsSaid() async {
        let fake = FakeCloudDrive([.google: .on()])
        fake.exportError = APIError.server(status: 404, message: "File not found")
        await cloudExport(fake) { model in
            await model.export(path: "x.pdf", to: .google)
            XCTAssertNil(model.exported)
            XCTAssertEqual(model.error, "File not found")
        }
    }

    func testDriveLinkMustBeHTTPS() {
        XCTAssertNil(CloudExportModel.driveLink("http://drive.google.com/x"))
        XCTAssertNil(CloudExportModel.driveLink(nil))
        XCTAssertNotNil(CloudExportModel.driveLink("https://onedrive.live.com/"))
    }
}

@MainActor
private func cloudImport(
    _ fake: FakeCloudDrive, destination: String? = nil,
    _ body: @MainActor (CloudImportModel) async -> Void
) async {
    await body(CloudImportModel(service: fake, destination: destination))
}

@MainActor
private func cloudExport(_ fake: FakeCloudDrive, _ body: @MainActor (CloudExportModel) async -> Void) async {
    await body(CloudExportModel(service: fake))
}
