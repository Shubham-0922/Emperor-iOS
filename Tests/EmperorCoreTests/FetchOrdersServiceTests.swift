import XCTest
@testable import EmperorCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// `POST /court/lookup` on the wire: the card it sends, and every refusal it can answer.
final class FetchOrdersServiceTests: XCTestCase {

    private static let config = APIConfig(baseURL: URL(string: "https://example.test/api")!)

    override func setUp() {
        super.setUp()
        HTTPStub.reset()
    }

    override func tearDown() {
        HTTPStub.reset()
        super.tearDown()
    }

    private func makeService() async -> FetchOrdersService {
        let client = APIClient(config: Self.config, session: HTTPStub.session())
        await client.setCredentials(Credentials(token: "tok-abc", userID: 42))
        return FetchOrdersService(client: client)
    }

    private func sentBody() throws -> [String: Any] {
        let body = try XCTUnwrap(HTTPStub.lastRequest?.httpBody)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
    }

    private static let recordJSON = #"""
        {"success":true,"cached":true,"record":{"case":{"title":"A vs. B","courtType":"sc","status":"Pending","nextHearing":null},
        "parties":{"petitioners":["A",null],"respondents":["B"]},
        "hearings":[{"date":"2026-10-01","purpose":"MENTION"}],"orders":[{"date":null,"title":"O","url":null}]}}
        """#

    func testARecordIsReadAndTheCardIsSentAsThePlatformsCasePayload() async throws {
        HTTPStub.always(.json(Self.recordJSON))
        let service = await makeService()
        var card = lookupCard(cnr: nil, diary: "41207/2025")
        card.scrapeRef = .object(["cino": .string("X1")])
        card.status = ""
        let result = try await service.lookup(card)

        XCTAssertTrue(result.cached)
        XCTAssertEqual(result.record.case.title, "A vs. B")
        XCTAssertEqual(result.record.parties.petitioners, ["A"], "a null name is dropped, not fatal")
        XCTAssertTrue(result.record.applications.isEmpty, "a missing list is empty")
        XCTAssertEqual(result.record.orders.count, 1)

        let request = try XCTUnwrap(HTTPStub.lastRequest)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/api/court/lookup")
        XCTAssertEqual(request.timeoutInterval, 90)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer tok-abc")
        let body = try sentBody()
        XCTAssertEqual(body["userId"] as? String, "42")
        let sent = try XCTUnwrap(body["card"] as? [String: Any])
        // `cnr || diaryNumber`: a court with no CNR is found again by its diary number.
        XCTAssertEqual(sent["cnr"] as? String, "41207/2025")
        XCTAssertEqual(sent["diaryNumber"] as? String, "41207/2025")
        XCTAssertEqual(sent["courtType"] as? String, "hc")
        XCTAssertEqual(sent["caseNumber"] as? String, "12")
        XCTAssertTrue(sent["status"] is NSNull, "a blank goes as null")
        XCTAssertTrue(sent["judge"] is NSNull)
        XCTAssertEqual((sent["scrapeRef"] as? [String: Any])?["cino"] as? String, "X1", "scrapeRef travels verbatim")
    }

    func testEachRefusalIsClassified() async {
        let cases: [(Int, String, LookupFailure)] = [
            (404, #"{"success":false,"code":"NOT_FOUND","error":"None."}"#, .notFound("None.")),
            (400, #"{"success":false,"code":"BAD_REQUEST","error":"Pick a court."}"#, .badRequest("Pick a court.")),
            (429, #"{"success":false,"code":"RATE_LIMIT","error":"Wait."}"#, .rateLimited("Wait.")),
            (502, #"{"success":false,"code":"COURT_DOWN","error":"Down."}"#, .courtDown("Down.")),
            (401, #"{"success":false,"code":"AUTH","error":"Sign in."}"#, .auth("Sign in.")),
            (403, #"{"success":false,"error":"Not yours."}"#, .other("Not yours.")),
            (500, #"{"success":false,"error":"boom"}"#, .other("boom")),
            (500, "<html>", .other(LookupFailure.fallbackMessage)),
            (200, #"{"success":true}"#, .other(LookupFailure.fallbackMessage)),
        ]
        let service = await makeService()
        for (status, body, expected) in cases {
            HTTPStub.always(.json(body, status: status))
            do {
                _ = try await service.lookup(lookupCard())
                XCTFail("\(status) \(body) succeeded")
            } catch let failure as LookupFailure {
                XCTAssertEqual(failure, expected, "\(status) \(body)")
            } catch {
                XCTFail("\(status): \(error)")
            }
        }
    }

    func testANetworkFailureIsWordedAsOne() async {
        HTTPStub.fail(URLError(.timedOut))
        let service = await makeService()
        do {
            _ = try await service.lookup(lookupCard())
            XCTFail("succeeded")
        } catch let failure as LookupFailure {
            XCTAssertTrue(failure.retryable)
            XCTAssertFalse(failure.message.isEmpty)
        } catch {
            XCTFail("\(error)")
        }
    }

    func testSignedOutSendsNothing() async {
        let client = APIClient(config: Self.config, session: HTTPStub.session())
        let service = FetchOrdersService(client: client)
        do {
            _ = try await service.lookup(lookupCard())
            XCTFail("succeeded")
        } catch let failure as LookupFailure {
            if case .auth = failure {} else { XCTFail("\(failure)") }
        } catch {
            XCTFail("\(error)")
        }
        XCTAssertTrue(HTTPStub.seen.isEmpty)
    }
}
