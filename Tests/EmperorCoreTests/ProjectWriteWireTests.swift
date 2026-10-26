import XCTest
@testable import EmperorCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Every matter write, as it goes on the wire: method, path, body keys (`userId` as text, `null`
/// where the route needs the key), the `DELETE /project` confirm encoding, and the refresh's 429
/// and 502 kept apart from a failure.
final class ProjectWriteWireTests: XCTestCase {

    private static let config = APIConfig(baseURL: URL(string: "https://example.test/api")!)

    override func setUp() {
        super.setUp()
        HTTPStub.reset()
    }

    override func tearDown() {
        HTTPStub.reset()
        super.tearDown()
    }

    private func makeService() async -> ProjectWriteService {
        let client = APIClient(config: Self.config, session: HTTPStub.session())
        await client.setCredentials(Credentials(token: "tok-abc", userID: 42))
        return ProjectWriteService(client: client)
    }

    private static let projectReply = #"{"success":true,"project":{"id":"prj-1","name":"M"}}"#

    private var last: URLRequest { HTTPStub.lastRequest ?? URLRequest(url: URL(string: "about:blank")!) }

    private var rawBody: String { String(decoding: last.httpBody ?? Data(), as: UTF8.self) }

    // MARK: - The matter

    func testANewMatterSendsItsNameBannerColourAndCourtStatusWithTheCallerAsText() async throws {
        let service = await makeService()
        HTTPStub.always(.json(Self.projectReply))

        let project = try await service.save(.newMatter(name: "Bhalla v. State", banner: "teal", color: nil, notFiled: true))

        XCTAssertEqual(project.id, "prj-1")
        XCTAssertEqual(last.httpMethod, "POST")
        XCTAssertEqual(last.path, "/api/project")
        let body = last.bodyJSON
        XCTAssertEqual(body["userId"] as? String, "42", "userId must be the token's id, as text")
        XCTAssertEqual(body["name"] as? String, "Bhalla v. State")
        XCTAssertEqual(body["banner"] as? String, "teal")
        XCTAssertTrue(body["color"] is NSNull)
        XCTAssertEqual(body["courtStatus"] as? String, "not_filed")
        XCTAssertNil(body["id"], "a create carries no id")
        XCTAssertEqual(Set(body.keys), ["userId", "name", "banner", "color", "courtStatus"])
    }

    /// The edit form's body is the web's `fieldsFromDraft` for the row it opened with — every
    /// field, key for key, so a cleared field is cleared rather than silently kept.
    func testAnEditSendsEveryFieldOfTheDraft() async throws {
        let row = Project(
            id: "prj-writ", name: " Bhalla v. State ", client: "Ankit Bhalla", notes: "Tender",
            forumType: "high_court", forumName: "Punjab and Haryana High Court", caseNumber: "4412",
            caseYear: "2025", caseType: "CWP", cnr: "PHHC010044122025", stage: "Admission", status: "active",
            priority: "high", nextHearingDateRaw: "2026-10-14T00:00:00.000Z",
            linkedCaseID: "case-x", color: "#ff0000", banner: nil, practiceArea: "writ", ourSide: "Caveator",
            courtStatus: "not_filed", oppositeParty: "State of Haryana")
        let draft = MatterDraft(row)
        XCTAssertEqual(draft.ourSide, "other")
        XCTAssertEqual(draft.ourSideText, "Caveator")
        XCTAssertNil(draft.color, "a colour outside the eight keys is no colour")
        XCTAssertEqual(draft.banner, "navy")

        let service = await makeService()
        HTTPStub.always(.json(Self.projectReply))
        _ = try await service.save(draft.body(banner: draft.banner))

        let expected: [String: Any] = [
            "userId": "42", "id": "prj-writ", "name": "Bhalla v. State", "client": "Ankit Bhalla",
            "description": "Tender", "forumType": "high_court", "forumName": "Punjab and Haryana High Court",
            "caseType": "CWP", "caseNumber": "4412", "caseYear": "2025", "cnr": "PHHC010044122025",
            "stage": "Admission", "status": "active", "priority": "high", "nextHearingDate": "2026-10-14",
            "filingDate": "", "practiceArea": "writ", "ourSide": "Caveator", "oppositeParty": "State of Haryana",
            "color": NSNull(), "banner": "navy", "courtStatus": "not_filed", "linkedCaseId": "case-x",
        ]
        let body = last.bodyJSON
        XCTAssertEqual(Set(body.keys), Set(expected.keys))
        XCTAssertEqual(NSDictionary(dictionary: body), NSDictionary(dictionary: expected))
    }

    func testABlankRowStillSendsEveryKeyWithTheServersDefaults() {
        let body = MatterDraft(Project(id: "p")).body(banner: "navy").json
        XCTAssertEqual(body["forumType"], .string("other"))
        XCTAssertEqual(body["status"], .string("active"))
        XCTAssertEqual(body["priority"], .string("normal"))
        XCTAssertEqual(body["courtStatus"], .null, "a taken-back \"not filed\" must be cleared, not left")
        XCTAssertEqual(body["ourSide"], .string(""))
        XCTAssertNil(body["linkedCaseId"])
        XCTAssertEqual(body.count, 21)
    }

    func testAPatchSendsNullToClearAndLeavesEverythingElseOut() async throws {
        let service = await makeService()
        HTTPStub.always(.json(Self.projectReply))

        _ = try await service.patch(projectID: "prj-1", fields: .courtStatus(nil))

        XCTAssertEqual(last.path, "/api/project-patch")
        XCTAssertTrue(rawBody.contains(#""courtStatus":null"#), rawBody)
        let fields = last.bodyJSON["fields"] as? [String: Any]
        XCTAssertEqual(fields?.count, 1)
        XCTAssertEqual(last.bodyJSON["projectId"] as? String, "prj-1")

        _ = try await service.patch(projectID: "prj-1", fields: .status(.archived))
        XCTAssertEqual((last.bodyJSON["fields"] as? [String: Any])?["status"] as? String, "archived")
    }

    func testAnUnknownPatchKeyIsRefusedWithoutARequest() async {
        let service = await makeService()
        HTTPStub.always(.json(Self.projectReply))
        do {
            _ = try await service.patch(projectID: "p", fields: ProjectFields(["linkedCaseId": .text("x")]))
            XCTFail("an unknown key was sent")
        } catch {
            XCTAssertEqual(DisplayText.message(for: error), "Unknown project field: linkedCaseId")
        }
        XCTAssertTrue(HTTPStub.seen.isEmpty)
    }

    /// A `+` left as it is reads as a space on the server, so "A+B" could never be confirmed.
    func testDeleteSendsTheExactNameWithPlusEncoded() async throws {
        let service = await makeService()
        HTTPStub.always(.json(#"{"success":true,"deleted":{"chats":2,"tasks":1,"storage":true,"index":null}}"#))

        let summary = try await service.delete(projectID: "prj-1", confirmName: "Bhalla+Sons & Co = 1")

        XCTAssertEqual(last.httpMethod, "DELETE")
        XCTAssertEqual(last.path, "/api/project")
        let query = last.url?.query ?? ""
        XCTAssertTrue(query.contains("confirm=Bhalla%2BSons%20%26%20Co%20%3D%201"), query)
        XCTAssertFalse(query.contains("+"), query)
        XCTAssertEqual(last.queryItems["confirm"], "Bhalla+Sons & Co = 1")
        XCTAssertEqual(last.queryItems["id"], "prj-1")
        XCTAssertEqual(last.queryItems["userId"], "42")
        XCTAssertEqual(summary.chats, 2)
        XCTAssertEqual(summary.storage, true)
    }

    func testAWrongNameComesBackInTheServersWords() async {
        let service = await makeService()
        HTTPStub.always(.json(
            #"{"success":false,"error":"To delete this project, send confirm= with its exact name"}"#, status: 400))
        do {
            _ = try await service.delete(projectID: "prj-1", confirmName: "nope")
            XCTFail("a refused delete succeeded")
        } catch {
            XCTAssertEqual(DisplayText.message(for: error), "To delete this project, send confirm= with its exact name")
        }
        XCTAssertEqual(HTTPStub.seen.count, 1, "a refused write must not be retried")
    }

    // MARK: - Banner

    func testABannerGoesUpAsADataURL() async throws {
        let service = await makeService()
        HTTPStub.always(.json(#"{"success":true,"banner":"image"}"#))
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10])

        try await service.uploadBanner(projectID: "prj-1", jpegOrPNG: jpeg, mime: "image/png")

        XCTAssertEqual(last.path, "/api/project-banner")
        XCTAssertEqual(last.bodyJSON["projectId"] as? String, "prj-1")
        XCTAssertEqual(last.bodyJSON["dataUrl"] as? String, "data:image/jpeg;base64,\(jpeg.base64EncodedString())",
                       "the declared type follows the bytes")
        XCTAssertGreaterThanOrEqual(last.timeoutInterval, 120)

        try await service.removeBanner(projectID: "prj-1")
        XCTAssertEqual(last.httpMethod, "DELETE")
        XCTAssertEqual(last.path, "/api/project-banner")
        XCTAssertEqual(last.queryItems["id"], "prj-1")
    }

    func testABannerTheServerWouldRefuseIsNotSent() async {
        let service = await makeService()
        HTTPStub.always(.json(#"{"success":true}"#))
        var big = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        big.append(Data(count: 2 * 1024 * 1024))
        for (bytes, message) in [(big, "The banner image must be 2 MB or smaller"),
                                 (Data("GIF89a....".utf8), "The banner must be a PNG, JPEG or WebP image")] {
            do {
                try await service.uploadBanner(projectID: "p", jpegOrPNG: bytes, mime: "image/png")
                XCTFail("sent")
            } catch {
                XCTAssertEqual((error as? MatterRuleError)?.message, message)
            }
        }
        XCTAssertTrue(HTTPStub.seen.isEmpty)
    }

    // MARK: - Chronology, tasks, ledger, people

    func testTheChildWritesGoToTheirRoutesWithTheirBodies() async throws {
        let service = await makeService()
        HTTPStub.respond { request in
            switch request.url?.path ?? "" {
            case "/api/project-update":
                return .json(#"{"success":true,"id":"pup-1","update":{"id":"pup-1","kind":"hearing"},"nextHearingDate":"2026-11-02"}"#)
            case "/api/project-task": return .json(#"{"success":true,"task":{"id":"pt-1","status":"done"}}"#)
            case "/api/project-ledger": return .json(#"{"success":true,"entry":{"id":"pl-1","amount_paise":2500050,"amount":25000.5}}"#)
            case "/api/project-person": return .json(#"{"success":true,"person":{"id":"pp-1","name":"A"}}"#)
            default: return .json(#"{"success":true}"#)
            }
        }

        var entry = ChronologyDraft(today: "2026-10-27")
        entry.kind = "hearing"
        entry.title = "Arguments"
        entry.precision = .month
        let saved = try await service.saveUpdate(entry.body(projectID: "prj-1"))
        XCTAssertEqual(saved.nextHearingDate, "2026-11-02")
        XCTAssertEqual(last.path, "/api/project-update")
        XCTAssertEqual(last.bodyJSON["eventDate"] as? String, "2026-10")
        XCTAssertEqual(last.bodyJSON["source"] as? String, "manual")
        XCTAssertNil(last.bodyJSON["id"], "a new entry carries no id")
        XCTAssertEqual(last.bodyJSON["userId"] as? String, "42")

        var task = TaskDraft(kind: "limitation")
        task.title = "Appeal"
        task.dueDate = "2026-11-30"
        let savedTask = try await service.saveTask(task.body(projectID: "prj-1"))
        XCTAssertEqual(savedTask.status, "done")
        XCTAssertEqual(Set(last.bodyJSON.keys), ["userId", "projectId", "title", "notes", "dueDate", "kind", "priority", "status"])
        XCTAssertEqual(last.bodyJSON["priority"] as? String, "high")

        var fee = LedgerDraft(kind: "fee", today: "2026-10-27")
        fee.reference = "kept?"
        _ = try await service.saveLedger(fee.body(projectID: "prj-1", rupees: 25000.5))
        XCTAssertEqual(last.bodyJSON["amount"] as? Double, 25000.5)
        XCTAssertTrue(last.bodyJSON["mode"] is NSNull, "a fee carries no payment mode")
        XCTAssertTrue(last.bodyJSON["category"] is NSNull)
        XCTAssertEqual(last.bodyJSON["reference"] as? String, "")

        var person = PersonDraft(role: "client", name: " Ankit ")
        person.id = "pp-1"
        _ = try await service.savePerson(person.body(projectID: "prj-1"))
        XCTAssertEqual(last.bodyJSON["id"] as? String, "pp-1")
        XCTAssertEqual(last.bodyJSON["name"] as? String, "Ankit")

        for (call, path) in [
            ({ try await service.deleteUpdate(id: "x1") }, "/api/project-update"),
            ({ try await service.deleteTask(id: "x1") }, "/api/project-task"),
            ({ try await service.deleteLedger(id: "x1") }, "/api/project-ledger"),
            ({ try await service.deletePerson(id: "x1") }, "/api/project-person"),
        ] as [(() async throws -> Void, String)] {
            try await call()
            XCTAssertEqual(last.httpMethod, "DELETE")
            XCTAssertEqual(last.path, path)
            XCTAssertEqual(last.queryItems["id"], "x1")
            XCTAssertEqual(last.queryItems["userId"], "42")
            XCTAssertNil(last.httpBody)
        }
    }

    func testAMissingRowIsTheServersSentence() async {
        let service = await makeService()
        HTTPStub.always(.json(#"{"success":false,"error":"Task not found"}"#, status: 404))
        do {
            try await service.deleteTask(id: "gone")
            XCTFail("expected a refusal")
        } catch {
            XCTAssertEqual(DisplayText.message(for: error), "Task not found")
        }
    }

    // MARK: - The court case

    /// The route refuses a body without `caseId`; a synthesized encoder would drop the nil.
    func testUnlinkingSendsAnExplicitNull() async throws {
        let service = await makeService()
        HTTPStub.always(.json(Self.projectReply))

        _ = try await service.linkCase(projectID: "prj-1", caseID: nil)

        XCTAssertEqual(last.path, "/api/project-link-case")
        XCTAssertTrue(rawBody.contains(#""caseId":null"#), rawBody)
        XCTAssertTrue(last.bodyJSON.keys.contains("caseId"))

        _ = try await service.linkCase(projectID: "prj-1", caseID: "case-9")
        XCTAssertEqual(last.bodyJSON["caseId"] as? String, "case-9")
    }

    func testLinkingAnotherTeamsCaseSaysWhy() async {
        let service = await makeService()
        HTTPStub.always(.json(#"{"success":false,"error":"You are not a member of the team that tracks that case"}"#, status: 403))
        do {
            _ = try await service.linkCase(projectID: "prj-1", caseID: "case-sc")
            XCTFail("expected a refusal")
        } catch {
            XCTAssertEqual(DisplayText.message(for: error), ProjectWriteService.notOnTheTeam)
        }
    }

    func testAMatterFromACaseSaysWhetherItExisted() async throws {
        let service = await makeService()
        HTTPStub.always(.json(#"{"success":true,"project":{"id":"prj-writ"},"existed":true}"#))

        let made = try await service.projectFromCase(caseID: "case-x", name: "  ", banner: "teal", color: nil)

        XCTAssertTrue(made.existed)
        XCTAssertEqual(made.project.id, "prj-writ")
        XCTAssertEqual(last.path, "/api/project-from-case")
        XCTAssertNil(last.bodyJSON["name"], "a blank name lets the server name it after the cause title")
        XCTAssertEqual(last.bodyJSON["caseId"] as? String, "case-x")
        XCTAssertEqual(last.bodyJSON["banner"] as? String, "teal")
    }

    func testARefreshReportsDoneTooSoonAndACourtFailureApart() async throws {
        let service = await makeService()

        HTTPStub.always(.json(#"{"success":true,"lastSyncedAt":"2026-10-27T05:00:00.000Z","counts":{"hearings":3,"orders":1}}"#))
        let done = try await service.refreshCase(projectID: "prj-1")
        XCTAssertEqual(done, .done(lastSyncedAt: "2026-10-27T05:00:00.000Z", counts: RefreshCounts(hearings: 3, orders: 1)))
        XCTAssertEqual(last.path, "/api/project-case-refresh")
        XCTAssertEqual(last.bodyJSON["projectId"] as? String, "prj-1")
        XCTAssertEqual(last.bodyJSON["userId"] as? String, "42")
        XCTAssertGreaterThanOrEqual(last.timeoutInterval, 170)
        XCTAssertEqual(RefreshCounts(hearings: 3, orders: 1).text, "Court record refreshed — 3 hearings, 1 order")

        HTTPStub.always(.json(
            #"{"success":false,"error":"This case was refreshed a moment ago — try again in 4 min","retryAfter":240}"#, status: 429))
        let soon = try await service.refreshCase(projectID: "prj-1")
        XCTAssertEqual(soon, .tooSoon(retryAfter: 240, message: "This case was refreshed a moment ago — try again in 4 min"))

        HTTPStub.always(.json(#"{"success":false,"error":"The court site did not answer in time"}"#, status: 502))
        let failed = try await service.refreshCase(projectID: "prj-1")
        XCTAssertEqual(failed, .courtFailed(message: "The court site did not answer in time"))

        XCTAssertEqual(HTTPStub.seen.count, 3, "each refresh is one request, never retried")
    }

    func testRetrySecondsAreReadDefensively() {
        XCTAssertEqual(RefreshOutcome.retrySeconds(nil), 300)
        XCTAssertEqual(RefreshOutcome.retrySeconds(-4), 300)
        XCTAssertEqual(RefreshOutcome.retrySeconds(239.2), 240)
        XCTAssertEqual(RefreshOutcome.retrySeconds(240_000), 240, "milliseconds read as seconds")
        XCTAssertEqual(RefreshOutcome.clock(240), "4:00")
        XCTAssertEqual(RefreshOutcome.clock(65), "1:05")
    }
}
