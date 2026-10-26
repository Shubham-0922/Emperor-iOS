import XCTest
@testable import EmperorCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The analysis routes on the wire, against `HTTPStub`.
final class AnalysisServiceTests: XCTestCase {

    private static let config = APIConfig(baseURL: URL(string: "https://example.test/api")!)

    override func setUp() {
        super.setUp()
        HTTPStub.reset()
    }

    override func tearDown() {
        HTTPStub.reset()
        super.tearDown()
    }

    private func service() async -> AnalysisService {
        let client = APIClient(config: Self.config, session: HTTPStub.session())
        await client.setCredentials(Credentials(token: "tok", userID: 42))
        return AnalysisService(client: client)
    }

    private func query(_ request: URLRequest?) -> [String: String] {
        guard let url = request?.url,
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        else { return [:] }
        return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
    }

    func testStartSendsTheToolTheDocumentsAndTheNote() async throws {
        HTTPStub.always(.json(#"{"success":true,"jobId":"9f1c"}"#, status: 202))
        let id = try await service().start(
            .listOfDates,
            files: [ChatAttachment(name: "Plaint.pdf", folderName: "Bakshi")],
            reference: "We act for Bakshi.", chatID: "chat-1")
        XCTAssertEqual(id, "9f1c")
        let request = try XCTUnwrap(HTTPStub.lastRequest)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/api/analysis/start")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any])
        XCTAssertEqual(Set(body.keys), ["userId", "tool", "chatId", "files", "reference"])
        XCTAssertEqual(body["userId"] as? String, "42")
        XCTAssertEqual(body["tool"] as? String, "list-of-dates")
        XCTAssertEqual(body["chatId"] as? String, "chat-1")
        XCTAssertEqual(body["reference"] as? String, "We act for Bakshi.")
        let files = try XCTUnwrap(body["files"] as? [[String: String]])
        XCTAssertEqual(files, [["name": "Plaint.pdf", "folderName": "Bakshi"]])
    }

    func testTheMonthsLimitIsARefusalNotAnError() async {
        HTTPStub.always(.json(
            #"{"success":false,"error":"This month’s queries are used up. Upgrade your plan to keep going.","code":"LIMIT"}"#,
            status: 402))
        do {
            _ = try await service().start(.docIndex, files: [], reference: "", chatID: "c")
            XCTFail("expected a refusal")
        } catch let error as APIError {
            XCTAssertEqual(error.refusal?.code, .queryLimit)
            XCTAssertEqual(error.refusal?.status, 402)
            XCTAssertEqual(error.refusal?.concernsThePlan, true)
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testAToolOutsideThePlanIsACodedRefusal() async {
        HTTPStub.always(.json(
            #"{"error":"Analysis is part of the paid plans. Upgrade to use it.","code":"FEATURE_NOT_IN_PLAN"}"#,
            status: 402))
        do {
            _ = try await service().start(.devilsAdvocate, files: [], reference: "", chatID: "c")
            XCTFail("expected a refusal")
        } catch let error as APIError {
            XCTAssertEqual(error.refusal?.code, .featureNotInPlan)
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testAJobPollCarriesTheUserAndTheID() async throws {
        HTTPStub.always(.json(#"{"success":true,"status":"thinking","stage":"Spotting every date","progress":0.4}"#))
        let job = try await service().job(id: "9f1c")
        XCTAssertEqual(job.phase, .running)
        XCTAssertEqual(job.stage, "Spotting every date")
        XCTAssertEqual(job.progress, 0.4)
        XCTAssertEqual(HTTPStub.lastRequest?.url?.path, "/api/analysis/job")
        XCTAssertEqual(query(HTTPStub.lastRequest), ["userId": "42", "id": "9f1c"])
    }

    func testAFailedJobIsA200WithStatusError() async throws {
        HTTPStub.always(.json(
            #"{"success":true,"status":"error","stage":"Stopped","progress":0.6,"error":"This analysis would cost more than its limit of $2.00.","usage":{"model":"m","inputTokens":10,"outputTokens":2,"costUsd":0.01}}"#))
        let job = try await service().job(id: "9f1c")
        XCTAssertEqual(job.phase, .failed)
        XCTAssertEqual(job.error, "This analysis would cost more than its limit of $2.00.")
        XCTAssertEqual(job.usage?.inputTokens, 10)
    }

    func testADoneJobCarriesItsResultAndRunID() async throws {
        HTTPStub.always(.json(#"{"success":true,"status":"done","stage":"Done","progress":1,"result":{"entries":[]},"runId":"anr_1"}"#))
        let job = try await service().job(id: "9f1c")
        XCTAssertEqual(job.phase, .done)
        XCTAssertEqual(job.runId, "anr_1")
        XCTAssertEqual(job.result, .object(["entries": .array([])]))
    }

    func testAnUnknownStatusIsStillRunning() {
        XCTAssertEqual(AnalysisJob(status: "queued").phase, .running)
        XCTAssertEqual(AnalysisJob(status: "").phase, .running)
    }

    func testAGoneJobSaysSo() async {
        HTTPStub.always(.json(
            #"{"success":false,"error":"This analysis is no longer running (it finished over an hour ago, or the server restarted). Run it again."}"#,
            status: 404))
        do {
            _ = try await service().job(id: "x")
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(
                DisplayText.message(for: error),
                "This analysis is no longer running (it finished over an hour ago, or the server restarted). Run it again.")
        }
    }

    func testSuccessFalseOnA2xxThrows() async {
        HTTPStub.always(.json(#"{"success":false,"error":"Saved analyses are not available right now"}"#))
        do {
            _ = try await service().history(.docIndex)
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? APIError, .server(status: 200, message: "Saved analyses are not available right now"))
        }
    }

    func testHistoryListsTheToolsRunsAndSkipsABrokenOne() async throws {
        HTTPStub.always(.json(#"""
            {"success":true,"runs":[
             {"id":"anr_2","tool":"doc-index","title":"Suit bundle","createdAt":"2026-10-20T09:30:00.000Z","fileNames":["a.pdf","b.pdf"],"reference":"","usage":null},
             "junk",
             {"id":"anr_1","tool":"doc-index","title":"","createdAt":"2026-10-19T09:30:00.000Z","fileNames":["c.pdf"]}]}
            """#))
        let runs = try await service().history(.docIndex)
        XCTAssertEqual(runs.map(\.id), ["anr_2", "anr_1"])
        XCTAssertEqual(runs[1].displayTitle, "c.pdf")
        XCTAssertEqual(runs[0].createdDate, WireDate.parse("2026-10-20T09:30:00.000Z"))
        XCTAssertEqual(query(HTTPStub.lastRequest), ["userId": "42", "tool": "doc-index"])
    }

    func testARunComesWithItsResult() async throws {
        HTTPStub.always(.json(#"{"success":true,"run":{"id":"anr_1","tool":"list-of-dates","title":"T","createdAt":"2026-10-20T09:30:00.000Z","fileNames":["a.pdf"],"reference":"note","usage":null,"result":{"entries":[]}}}"#))
        let run = try await service().run(id: "anr_1")
        XCTAssertEqual(run.id, "anr_1")
        XCTAssertEqual(run.fileNames, ["a.pdf"])
        XCTAssertEqual(run.reference, "note")
        XCTAssertEqual(run.result, .object(["entries": .array([])]))
        XCTAssertEqual(HTTPStub.lastRequest?.url?.path, "/api/analysis/run")
    }

    func testDeletingARunThatIsGoneIsFine() async throws {
        HTTPStub.always(.json(#"{"success":false,"error":"No such saved analysis."}"#, status: 404))
        try await service().deleteRun(id: "anr_1")
        XCTAssertEqual(HTTPStub.lastRequest?.httpMethod, "DELETE")
        XCTAssertEqual(query(HTTPStub.lastRequest), ["userId": "42", "id": "anr_1"])
    }

    func testDeletingCanFail() async {
        HTTPStub.always(.json(#"{"success":false,"error":"Internal error"}"#, status: 500))
        do {
            try await service().deleteRun(id: "anr_1")
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? APIError, .server(status: 500, message: "Internal error"))
        }
    }
}
