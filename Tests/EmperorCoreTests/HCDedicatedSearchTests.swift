import XCTest
@testable import EmperorCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The six High Courts with portals of their own — Delhi, Punjab & Haryana, Bombay, Karnataka,
/// Madras, Allahabad — searched on their own route, and the eCourts High Courts left as they were.
final class HCDedicatedSearchTests: XCTestCase {

    private static let config = APIConfig(baseURL: URL(string: "https://example.test/api")!)

    override func setUp() {
        super.setUp()
        HTTPStub.reset()
    }

    override func tearDown() {
        HTTPStub.reset()
        super.tearDown()
    }

    private func dedicated(bench: Bool = false) -> CourtSearchQuery {
        var q = CourtSearchQuery(forum: .highCourt, courtID: "hc-delhi")
        q.highCourtDedicated = true
        q.requiresBench = bench
        q.stateCode = "26"
        q.courtName = "High Court — Delhi"
        return q
    }

    // MARK: - The query

    func testADedicatedCourtGoesToItsOwnRouteByCaseNumberOnly() {
        var q = dedicated()
        XCTAssertEqual(q.searchPath, "/court/hc/dedicated/search")
        XCTAssertEqual(q.availableModes, [.caseNumber])
        q.mode = .diaryNumber
        XCTAssertNil(q.searchPath)
        XCTAssertFalse(q.isComplete)
    }

    func testADedicatedCourtNeedsTypeNumberAndYearAndABenchOnlyWhenAsked() {
        var q = dedicated()
        XCTAssertEqual(q.missingFields, ["Case type", "Case number", "Year"])
        q.caseType = "W.P.(C)"
        q.number = "4410"
        q.year = "2025"
        XCTAssertTrue(q.isComplete, "no state, no eCourts bench: \(q.missingFields)")

        var seat = dedicated(bench: true)
        seat.caseType = "WP"
        seat.number = "1"
        seat.year = "2025"
        XCTAssertEqual(seat.missingFields, ["Bench"])
        seat.bench = "B"
        XCTAssertTrue(seat.isComplete)
    }

    func testTheDedicatedBodyIsThePlatformsOwn() {
        var q = dedicated(bench: true)
        q.caseType = "W.P.(C)"
        q.caseTypeLabel = "W.P.(C)"
        q.number = " 4410 "
        q.year = "2025"
        q.bench = "D"
        XCTAssertEqual(q.body, [
            "courtId": .string("hc-delhi"),
            "caseType": .string("W.P.(C)"),
            "caseTypeLabel": .string("W.P.(C)"),
            "caseNumber": .string("4410"),
            "year": .string("2025"),
            "bench": .string("D"),
            "courtName": .string("High Court — Delhi"),
        ])
    }

    func testAGenericHighCourtIsUnchanged() {
        var q = CourtSearchQuery(forum: .highCourt, courtID: "hc-kerala")
        q.stateCode = "4"
        XCTAssertEqual(q.searchPath, "/court/hc/search")
        XCTAssertEqual(q.availableModes, [.caseNumber, .diaryNumber])
        XCTAssertEqual(q.missingFields, ["Court", "Case type", "Case number", "Year"])
        q.mode = .diaryNumber
        XCTAssertEqual(q.searchPath, "/court/hc/diary")
    }

    // MARK: - The contract

    private func makeClient() async -> APIClient {
        let client = APIClient(config: Self.config, session: HTTPStub.session())
        await client.setCredentials(Credentials(token: "tok", userID: 1))
        return client
    }

    func testTheContractSaysWhichKindOfHighCourt() async throws {
        let metadata = CourtMetadataService(client: await makeClient())
        let delhi = try XCTUnwrap(CourtCatalogue.court("hc-delhi"))
        HTTPStub.always(.json(#"""
            {"success":true,"kind":"dedicated","contract":{"needsBench":false,"needsCaptcha":false,"caseTypeSource":"live"},
             "caseTypes":[{"value":"W.P.(C)","label":"W.P.(C)"}],"benches":[]}
            """#))
        let contract = try await metadata.contract(for: delhi)
        XCTAssertEqual(contract.hcKind, .dedicated)
        XCTAssertFalse(contract.needsBench)
        XCTAssertEqual(contract.caseTypes.map(\.value), ["W.P.(C)"])
        XCTAssertEqual(HTTPStub.lastRequest?.url?.path, "/api/court/hc/config")

        let kerala = try XCTUnwrap(CourtCatalogue.court("hc-kerala"))
        HTTPStub.always(.json(#"{"success":true,"kind":"generic","contract":{"needsBench":false},"stateCode":"4"}"#))
        let generic = try await metadata.contract(for: kerala)
        XCTAssertEqual(generic.hcKind, .generic)
        XCTAssertTrue(generic.needsBench, "an eCourts High Court always wants a bench")
    }

    // MARK: - The wire

    func testADedicatedSearchIsSentToItsRouteWithTheLongerWait() async throws {
        HTTPStub.always(.json(#"""
            {"success":true,"results":[{"courtType":"hc","courtCode":"hc-delhi","caseType":"W.P.(C)","caseNumber":"4410",
             "caseYear":"2025","title":"Mehta Traders vs. Union of India","preview":false,"source":"delhihighcourt"}]}
            """#))
        let service = CourtSearchService(client: await makeClient())
        var q = dedicated()
        q.caseType = "W.P.(C)"
        q.number = "4410"
        q.year = "2025"
        let found = try await service.search(q)
        XCTAssertEqual(found.map(\.title), ["Mehta Traders vs. Union of India"])
        let request = try XCTUnwrap(HTTPStub.lastRequest)
        XCTAssertEqual(request.url?.path, "/api/court/hc/dedicated/search")
        XCTAssertEqual(request.timeoutInterval, 90)
    }

    func testADedicatedNotFoundIsAnEmptyAnswer() async throws {
        HTTPStub.always(.json(#"{"success":false,"notFound":true,"error":"No case found."}"#))
        let service = CourtSearchService(client: await makeClient())
        var q = dedicated()
        q.caseType = "W.P.(C)"
        q.number = "1"
        q.year = "2025"
        let found = try await service.search(q)
        XCTAssertTrue(found.isEmpty)
    }

    // MARK: - The screen

    func testChoosingADedicatedCourtAsksForNoBenchesAndOffersOneMode() async {
        let metadata = DedicatedMetadata()
        metadata.contract = CourtContract(
            caseTypes: [CourtOption(value: "W.P.(C)", label: "W.P.(C)")], hcKind: .dedicated)
        await onMainActor {
            let vm = CourtSearchViewModel(service: NoSearch(), metadata: metadata)
            vm.setMode(.diaryNumber)
            await vm.selectCourt(CourtCatalogue.court("hc-delhi")!)
            XCTAssertTrue(vm.query.highCourtDedicated)
            XCTAssertFalse(vm.query.requiresBench)
            XCTAssertEqual(vm.query.mode, .caseNumber)
            XCTAssertEqual(vm.query.availableModes, [.caseNumber])
            XCTAssertEqual(vm.caseTypes.map(\.value), ["W.P.(C)"])
            XCTAssertEqual(metadata.benchesAsked, 0, "eCourts was asked for the benches of a dedicated court")
            XCTAssertTrue(vm.expectsLongWait)
        }
    }

    func testADedicatedSeatKeepsTheCaseType() async {
        let metadata = DedicatedMetadata()
        metadata.contract = CourtContract(
            needsBench: true, benches: [CourtOption(value: "L", label: "Lucknow")],
            caseTypes: [CourtOption(value: "WRIT", label: "Writ")], hcKind: .dedicated)
        await onMainActor {
            let vm = CourtSearchViewModel(service: NoSearch(), metadata: metadata)
            await vm.selectCourt(CourtCatalogue.court("hc-allahabad")!)
            vm.selectCaseType(CourtOption(value: "WRIT", label: "Writ"))
            await vm.selectBench(CourtOption(value: "L", label: "Lucknow"))
            XCTAssertEqual(vm.query.caseType, "WRIT")
            XCTAssertEqual(vm.query.bench, "L")
            XCTAssertEqual(metadata.caseTypesAsked, 0)
        }
    }

    func testAGenericBenchBecomesTheCourtCodeAndFetchesItsTypes() async {
        let metadata = DedicatedMetadata()
        metadata.contract = CourtContract(needsBench: true, hcKind: .generic)
        metadata.benches = [CourtOption(value: "2", label: "Principal Bench")]
        await onMainActor {
            let vm = CourtSearchViewModel(service: NoSearch(), metadata: metadata)
            await vm.selectCourt(CourtCatalogue.court("hc-kerala")!)
            XCTAssertEqual(metadata.benchesAsked, 1)
            XCTAssertEqual(vm.query.availableModes, [.caseNumber, .diaryNumber])
            await vm.selectBench(CourtOption(value: "2", label: "Principal Bench"))
            XCTAssertEqual(vm.query.courtCode, "2")
            XCTAssertEqual(metadata.caseTypesAsked, 1)
            vm.selectCaseType(CourtOption(value: "1", label: "WP(C)"))
            vm.query.number = "12"
            vm.query.year = "2025"
            XCTAssertTrue(vm.query.isComplete, "\(vm.query.missingFields)")
        }
    }
}

@MainActor
private func onMainActor(_ body: @MainActor () async -> Void) async {
    await body()
}

private final class DedicatedMetadata: CourtMetadataProviding, @unchecked Sendable {
    var contract = CourtContract()
    var benches: [CourtOption] = []
    private(set) var benchesAsked = 0
    private(set) var caseTypesAsked = 0

    func contract(for court: Court) async throws -> CourtContract { contract }
    func highCourtBenches(stateCode: String) async throws -> [CourtOption] {
        benchesAsked += 1
        return benches
    }
    func highCourtCaseTypes(stateCode: String, courtCode: String) async throws -> [CourtOption] {
        caseTypesAsked += 1
        return []
    }
    func tribunalCaseTypes(courtID: String, bench: String) async throws -> [CourtOption] { [] }
    func consumerStates() async throws -> [CourtOption] { [] }
    func consumerDistricts(stateID: String) async throws -> [CourtOption] { [] }
}

private struct NoSearch: CourtSearching {
    func search(_ query: CourtSearchQuery) async throws -> [CourtSearchResult] { [] }
    func startCaptchaSession() async throws -> SupremeCourtCaptcha {
        throw APIError.server(status: 500, message: "unused")
    }
    func submitCaptcha(_ answer: String, for query: CourtSearchQuery, session: String) async throws -> CaptchaOutcome {
        .results([])
    }
    func save(_ result: CourtSearchResult) async throws -> SaveCaseOutcome { .saved(id: "x") }
}
