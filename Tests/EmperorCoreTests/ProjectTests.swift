import XCTest
@testable import EmperorCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Matters ("projects" on the wire) are hand-made files — user-owned rows typed in by an advocate,
// as opposed to the team-owned rows the court scrapers fill in. Almost everything that can go
// wrong here goes wrong *silently*: a key spelled the way the rest of the API spells its keys
// decodes to nil, a count defaulted to zero states something the server never said. Each test is
// named for what a user sees when the rule it pins is broken. The list and workspace screens are
// held by `MattersListViewModelTests` and `MatterWorkspaceViewModelTests`; the full `/project`
// payload by `ProjectWireTests`.

// MARK: - Builders

private func project(
    _ id: String = "p1",
    name: String? = "Suvarnapatnam v. Ashwatth",
    caseType: String? = "ARB.P.",
    caseNumber: String? = "112",
    caseYear: String? = "2025",
    cnr: String? = nil,
    forumName: String? = "Delhi International Arbitration Centre",
    forumType: String? = "arbitration",
    priority: String? = "high",
    status: String? = nil
) -> Project {
    Project(
        id: id, name: name, client: "Suvarnapatnam Infra", forumType: forumType, forumName: forumName,
        caseNumber: caseNumber, caseYear: caseYear, caseType: caseType, cnr: cnr, status: status,
        priority: priority)
}

private func update(
    _ id: String = "u1",
    title: String? = "Counter-claim filed",
    body: String? = "Served on the other side the same day.",
    eventDate: String? = "2026-08-30"
) -> ProjectUpdate {
    ProjectUpdate(id: id, kind: "note", title: title, body: body, eventDateRaw: eventDate)
}

// MARK: - The wire

final class ProjectModelTests: XCTestCase {

    private func decodeList(_ json: String) throws -> ProjectListResponse {
        try JSONDecoder().decode(ProjectListResponse.self, from: Data(json.utf8))
    }

    private func decodeDetail(_ json: String) throws -> ProjectDetailResponse {
        try JSONDecoder().decode(ProjectDetailResponse.self, from: Data(json.utf8))
    }

    /// The list route selects `p.*`, so every column the schema ever gained rides out whether
    /// this build knows it or not — and a matter typed in half-finished is the normal case. A
    /// model that required any of these would fail the whole page because of one thin row.
    func testAMatterWithAlmostEveryFieldNullStillDecodes() throws {
        let response = try decodeList("""
            {"success":true,"projects":[{
              "id":"p1","user_id":"42","name":"Advisory brief","client":null,
              "description":null,"forum_type":"other","forum_name":null,"case_number":null,
              "case_year":null,"cnr":null,"stage":null,"status":"active","priority":"normal",
              "next_hearing_date":null,"filing_date":null,"linked_case_id":null,"color":null,
              "created_at":"2026-08-01T09:00:00.000Z","updated_at":"2026-08-01T09:00:00.000Z",
              "archived_at":null,"case_type":null,"banner":null,"practice_area":null,
              "our_side":null,"court_status":null,"opposite_party":null,
              "file_count":0,"chat_count":0,"update_count":0,"last_activity":null,
              "open_tasks":0,"next_task_due":null,"billed":0,"received":0}]}
            """)
        let matter = try XCTUnwrap(response.projects?.first)
        XCTAssertEqual(matter.displayName, "Advisory brief")
        XCTAssertEqual(matter.caseRef, "")
        // `other` is the server's default for "nobody said", not a court.
        XCTAssertEqual(matter.courtName, "")
        XCTAssertEqual(matter.fileCount, 0)
        XCTAssertEqual(matter.openTasks, 0)
        XCTAssertEqual(matter.billed, 0)
        XCTAssertEqual(matter.createdAtRaw, "2026-08-01T09:00:00.000Z")
    }

    /// The columns the list carries for its cards: banner, practice area, side, parties, the
    /// open-task count and the money.
    func testTheCardColumnsDecode() throws {
        let response = try decodeList("""
            {"success":true,"projects":[{"id":"p1","name":"Bhalla v. State","banner":"teal",
              "practice_area":"writ","our_side":"petitioner","court_status":"not_filed",
              "opposite_party":"State of Haryana","client":"Ankit Bhalla","open_tasks":2,
              "next_task_due":"2026-10-11","billed":25000.5,"received":10000,
              "archived_at":"2026-09-01T00:00:00.000Z"}]}
            """)
        let matter = try XCTUnwrap(response.projects?.first)
        XCTAssertEqual(matter.bannerPreset, .teal)
        XCTAssertEqual(matter.practiceArea, "writ")
        XCTAssertEqual(matter.clientLine, "Ankit Bhalla (Petitioner)")
        XCTAssertEqual(matter.oppositeParty, "State of Haryana")
        XCTAssertTrue(matter.isNotFiled)
        XCTAssertEqual(matter.openTasks, 2)
        XCTAssertEqual(matter.nextTaskDueRaw, "2026-10-11")
        XCTAssertEqual(matter.billed, 25000.5)
        XCTAssertEqual(matter.archivedAtRaw, "2026-09-01T00:00:00.000Z")
    }

    /// One row the model cannot read — here, no id at all — costs only that row.
    func testOneUnreadableRowDoesNotEmptyTheList() throws {
        let response = try decodeList("""
            {"success":true,"projects":[{"name":"No id"},{"id":"p2","name":"Kept"},42]}
            """)
        XCTAssertEqual(response.projects?.map(\.id), ["p2"])
    }

    /// Ids, case numbers and counts sent as numbers are read as their text and values.
    func testNumbersWhereTextWasExpectedAreRead() throws {
        let response = try decodeList("""
            {"success":true,"projects":[{"id":7,"case_number":4683,"case_year":2023,
              "case_type":"W.P.(C)","file_count":"3"}]}
            """)
        let matter = try XCTUnwrap(response.projects?.first)
        XCTAssertEqual(matter.id, "7")
        XCTAssertEqual(matter.caseRef, "W.P.(C) 4683/2023")
        XCTAssertEqual(matter.fileCount, 3)
    }

    /// The counts exist only on the list route. Defaulting them to zero would make the
    /// workspace claim "0 files" about a matter with seven.
    func testTheComputedCountsAreAbsentRatherThanZeroOnTheDetailRoute() throws {
        let response = try decodeDetail("""
            {"success":true,"project":{"id":"p1","name":"M"},"updates":[],"courtHistory":[]}
            """)
        let matter = try XCTUnwrap(response.project)
        XCTAssertNil(matter.fileCount)
        XCTAssertNil(matter.chatCount)
        XCTAssertNil(matter.openTasks)
        XCTAssertNil(matter.billed)
    }

    /// A failure with no `success` key reads as a failure, not as a missing field.
    func testAServerFailureCarriesNoSuccessKey() throws {
        let response = try decodeList(#"{"error":"Missing userId"}"#)
        XCTAssertNil(response.success)
        XCTAssertEqual(response.error, "Missing userId")
        XCTAssertThrowsError(
            try CaseService.throwIfUnsuccessful(
                success: response.success, error: response.error))
    }

    /// The wire key is `description`; the property is `notes`.
    func testTheDescriptionColumnLandsOnNotes() throws {
        let response = try decodeList("""
            {"success":true,"projects":[{"id":"p1","description":"Section 34 challenge."}]}
            """)
        XCTAssertEqual(response.projects?.first?.notes, "Section 34 challenge.")
    }

    // MARK: - Derived reading

    /// `caseRefOf`: the registry's form; the year only after a slash; the CNR without a number.
    func testTheCaseReferenceIsTheWebsOwn() {
        XCTAssertEqual(project(caseType: "ARB.P.", caseNumber: "112", caseYear: nil).caseRef, "ARB.P. 112")
        XCTAssertEqual(project(caseType: nil, caseNumber: "112", caseYear: "2025").caseRef, "112/2025")
        XCTAssertEqual(
            project(caseType: nil, caseNumber: nil, caseYear: nil, cnr: "DLHC010012342026").caseRef,
            "DLHC010012342026")
        XCTAssertEqual(project(caseType: "ARB.P.", caseNumber: nil, caseYear: nil).caseRef, "")
    }

    func testABlankNameReadsAsUntitled() {
        XCTAssertEqual(project(name: "   ").displayName, "Untitled matter")
    }

    /// The card's court line: the court's own name, else the forum's kind without its examples,
    /// never the default `other`.
    func testTheCourtLineIsTheNameThenTheForumKind() {
        XCTAssertEqual(project(forumName: "NCLT New Delhi Bench-III", forumType: "tribunal").courtName,
                       "NCLT New Delhi Bench-III")
        XCTAssertEqual(project(forumName: nil, forumType: "tribunal").courtName, "Tribunal")
        XCTAssertEqual(project(forumName: "", forumType: "other").courtName, "")
    }

    /// Who we act for, as the card says it: with a client, then in brackets; without, as a side.
    func testTheClientLineNamesTheSide() {
        var p = Project(id: "p", client: "Ankit Bhalla", ourSide: "respondent")
        XCTAssertEqual(p.clientLine, "Ankit Bhalla (Respondent)")
        p.client = nil
        XCTAssertEqual(p.clientLine, "For the respondent")
        p.ourSide = "the bank"
        XCTAssertEqual(p.clientLine, "For the the bank")
        p.ourSide = nil
        XCTAssertEqual(p.clientLine, "")
    }

    /// A status outside the vocabulary files under Active, as the web counts it.
    func testStatusKeysFallBackToActive() {
        XCTAssertEqual(project(status: "archived").statusKey, .archived)
        XCTAssertEqual(project(status: "on_hold").statusKey, .onHold)
        XCTAssertEqual(project(status: "pending").statusKey, .active)
        XCTAssertEqual(project(status: nil).statusKey, .active)
        XCTAssertTrue(project(status: "archived").isArchived)
        XCTAssertTrue(project(priority: "high").isHighPriority)
    }

    /// "Not filed yet" holds only while no case is linked.
    func testNotFiledYieldsToALinkedCase() {
        XCTAssertTrue(Project(id: "p", courtStatus: "not_filed").isNotFiled)
        XCTAssertFalse(Project(id: "p", linkedCaseID: "c1", courtStatus: "not_filed").isNotFiled)
    }

    /// An update sorts on when the thing happened, falling back to when it was recorded.
    func testAnUpdateFallsBackFromEventDateToCreatedAt() {
        XCTAssertNotNil(update(eventDate: "2026-08-30").day)
        let recordedOnly = ProjectUpdate(id: "u2", title: "Filed", createdAtRaw: "2026-08-29 11:02:00")
        XCTAssertNotNil(recordedOnly.day)
    }

    /// A row with nothing to draw is not drawn: an update needs a title or body; a court row a
    /// title, a subtitle or scraped data.
    func testEmptyRowsAreNotRenderable() {
        XCTAssertFalse(update(title: nil, body: nil).isRenderable)
        XCTAssertFalse(update(title: "  ", body: "").isRenderable)
        XCTAssertTrue(update(title: nil, body: "Served.").isRenderable)
        XCTAssertFalse(CourtHistoryItem(id: "i", section: "orders").isRenderable)
        XCTAssertTrue(CourtHistoryItem(id: "i", section: "hearings", data: ["purpose": .string("Arguments")]).isRenderable)
        XCTAssertTrue(CourtHistoryItem(id: "i", section: "orders", title: "Order").isRenderable)
    }

    /// The adapters hand the ports exactly what the row holds.
    func testTheAdaptersCarryEveryField() {
        let u = ProjectUpdate(id: "u", kind: "order", title: "T", body: "B", eventDateRaw: "2026-10-01",
                              createdAtRaw: "2026-10-02 10:00:00", source: "ai", sourceRef: "doc.pdf")
        XCTAssertEqual(u.recordUpdate, MatterRecord.Update(
            id: "u", kind: "order", title: "T", body: "B", eventDate: "2026-10-01",
            createdAt: "2026-10-02 10:00:00", source: "ai", sourceRef: "doc.pdf"))
        let l = LedgerEntry(id: "l", kind: "payment", amountPaise: 150_050, amount: 1500.5, entryDateRaw: "2026-10-01")
        XCTAssertEqual(l.ledgerEntry.amountPaise, 150_050)
        XCTAssertEqual(l.paise, 150_050)
        XCTAssertEqual(LedgerEntry(id: "x", kind: "fee", amount: 12.34).paise, 1234)
        let t = ProjectTask(id: "t", dueDateRaw: "2026-10-01", kind: "limitation", priority: "high", status: "open")
        XCTAssertEqual(t.taskKey.kind, "limitation")
        XCTAssertEqual(t.taskKey.dueDate, "2026-10-01")
    }
}

// MARK: - The routes

final class ProjectServiceWireTests: XCTestCase {

    private static let config = APIConfig(baseURL: URL(string: "https://example.test/api")!)

    override func setUp() {
        super.setUp()
        HTTPStub.reset()
    }

    override func tearDown() {
        HTTPStub.reset()
        super.tearDown()
    }

    private func makeService() async -> ProjectService {
        let client = APIClient(config: Self.config, session: HTTPStub.session())
        await client.setCredentials(Credentials(token: "tok-abc", userID: 42))
        return ProjectService(client: client)
    }

    /// The route reads the literal "1"; any other spelling is read as false.
    func testTheArchivedFlagIsOmittedByDefaultAndSentAsTheLiteralOne() async throws {
        let service = await makeService()
        HTTPStub.always(.json(#"{"success":true,"projects":[]}"#))

        _ = try await service.projects(includeArchived: false)
        XCTAssertEqual(HTTPStub.lastRequest?.path, "/api/projects")
        XCTAssertNil(HTTPStub.lastRequest?.queryItems["includeArchived"])

        _ = try await service.projects(includeArchived: true)
        XCTAssertEqual(HTTPStub.lastRequest?.queryItems["includeArchived"], "1")
    }

    func testTheCallerIdentityRidesOnEveryProjectRequest() async throws {
        let service = await makeService()
        HTTPStub.always(.json(#"{"success":true,"projects":[]}"#))

        _ = try await service.projects(includeArchived: false)

        let sent = try XCTUnwrap(HTTPStub.lastRequest)
        XCTAssertEqual(sent.queryItems["userId"], "42")
        XCTAssertEqual(sent.header("Authorization"), "Bearer tok-abc")
    }

    func testTheDetailRouteAsksByIdOnTheQueryString() async throws {
        let service = await makeService()
        HTTPStub.always(.json("""
            {"success":true,"project":{"id":"p1","name":"M"},"updates":[],"courtHistory":[]}
            """))

        _ = try await service.project(id: "p1")

        let sent = try XCTUnwrap(HTTPStub.lastRequest)
        XCTAssertEqual(sent.path, "/api/project")
        XCTAssertEqual(sent.queryItems["id"], "p1")
    }

    /// "Gone" and "not yours" are the same 404 with the server's word, reworded once here.
    func testAMissingOrForeignMatterGetsOneHonestSentence() async {
        let service = await makeService()
        HTTPStub.always(.json(#"{"success":false,"error":"Project not found"}"#, status: 404))

        do {
            _ = try await service.project(id: "p-someone-elses")
            XCTFail("expected a 404")
        } catch let error as APIError {
            XCTAssertEqual(error, .server(status: 404, message: ProjectService.projectGoneMessage))
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    /// A 404 with no envelope is a server without the route: a failure to load, not a deleted
    /// matter, so it keeps its own wording.
    func testABare404IsNotReadAsAMissingMatter() async {
        let service = await makeService()
        HTTPStub.always(.text("Cannot GET /project", status: 404))

        do {
            _ = try await service.project(id: "p1")
            XCTFail("expected a 404")
        } catch let error as APIError {
            XCTAssertNotEqual(error, .server(status: 404, message: ProjectService.projectGoneMessage))
            if case .server(404, _) = error {} else { XCTFail("not a 404: \(error)") }
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    /// A blank id never reaches the network.
    func testABlankIdIsRefusedWithoutASingleRequest() async {
        let service = await makeService()

        do {
            _ = try await service.project(id: "   ")
            XCTFail("expected a refusal")
        } catch let error as APIError {
            XCTAssertEqual(error, .server(status: 404, message: ProjectService.projectGoneMessage))
            XCTAssertTrue(HTTPStub.seen.isEmpty, "nothing should have gone on the wire")
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    /// Filtering in the service rather than the view keeps a count and its rows in step.
    func testUnrenderableRowsAreDroppedBeforeTheScreenEverSeesThem() async throws {
        let service = await makeService()
        HTTPStub.always(.json("""
            {"success":true,"project":{"id":"p1","name":"M"},
             "updates":[{"id":"u1","title":"Filed"},{"id":"u2","title":null,"body":"  "}],
             "courtHistory":[{"id":"i1","section":"orders","title":"Order dated 12.08.2026"},
                             {"id":"i2","section":"orders","title":null,"subtitle":null,"data":null}]}
            """))

        let detail = try await service.project(id: "p1")

        XCTAssertEqual(detail.updates.count, 1)
        XCTAssertEqual(detail.courtHistory.count, 1)
    }

    /// A 200 whose body has no project is not a success.
    func testASuccessfulResponseWithNoProjectIsStillAFailure() async {
        let service = await makeService()
        HTTPStub.always(.json(#"{"success":true,"updates":[],"courtHistory":[]}"#))

        do {
            _ = try await service.project(id: "p1")
            XCTFail("expected a refusal")
        } catch let error as APIError {
            XCTAssertEqual(error, .server(status: 404, message: ProjectService.projectGoneMessage))
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    /// The banner is asked for by id and version, with the session's bearer, and comes back as
    /// the picture's own bytes.
    func testTheBannerIsFetchedAsBytesWithTheBearer() async throws {
        let service = await makeService()
        let png = Data([0x89, 0x50, 0x4E, 0x47])
        HTTPStub.always(HTTPStub.Reply(status: 200, body: png, headers: ["Content-Type": "image/png"]))

        let data = try await service.bannerImage(projectID: "p1", version: "2026-10-01T00:00:00.000Z")

        XCTAssertEqual(data, png)
        let sent = try XCTUnwrap(HTTPStub.lastRequest)
        XCTAssertEqual(sent.path, "/api/project-banner")
        XCTAssertEqual(sent.queryItems["id"], "p1")
        XCTAssertEqual(sent.queryItems["v"], "2026-10-01T00:00:00.000Z")
        XCTAssertEqual(sent.header("Authorization"), "Bearer tok-abc")
    }

    func testAMatterWithoutABannerPictureFails() async {
        let service = await makeService()
        HTTPStub.always(.json(#"{"success":false,"error":"No banner"}"#, status: 404))
        do {
            _ = try await service.bannerImage(projectID: "p1", version: "")
            XCTFail("expected a failure")
        } catch {}
        XCTAssertNil(HTTPStub.lastRequest?.queryItems["v"])
    }
}

final class ProjectSessionWiringTests: XCTestCase {

    /// The service hangs off `Session`, on the same client as everything else — a second
    /// `APIClient` would carry no credentials.
    func testTheSessionExposesTheProjectServiceOnTheSharedClient() async {
        await withProjectSession { session in
            XCTAssertTrue(
                session.projects.client === session.client,
                "must share the one authenticated client")
        }
    }
}

/// Free function, not a method: an `XCTestCase` is not `Sendable`, so calling an instance helper
/// from a `@MainActor` closure makes Swift 6 reject the capture of `self`.
@MainActor
private func withProjectSession(_ body: @MainActor (Session) async -> Void) async {
    await body(Session(
        config: APIConfig(baseURL: URL(string: "https://example.test/api")!),
        store: InMemoryCredentialStore(),
        cache: ResponseCache(store: InMemoryCacheStore())))
}
