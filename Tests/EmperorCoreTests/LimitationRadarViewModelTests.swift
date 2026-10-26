import XCTest
@testable import EmperorCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor
private func onMain(_ body: @MainActor () async -> Void) async {
    await body()
}

private func audit(
    color: String = "red", status: String = "LEGALLY BARRED / EXPIRED", overdue: Int,
    adjusted: Int = 0, relies: Bool = false, mediation: LimitationAudit.Mediation? = nil
) -> LimitationAudit {
    LimitationAudit(
        status: status, statusColor: color, daysOverdue: overdue,
        curativeStrategies: ["one", "two"], bareDeadline: "2026-01-15",
        mediation: mediation, adjustedDeadline: "2026-03-16", adjustedDaysOverdue: adjusted,
        reliesOnMediationExclusion: relies)
}

@MainActor
private func ready(_ fake: FakeRadar) -> LimitationRadarViewModel {
    let vm = LimitationRadarViewModel(service: fake)
    vm.causeOfAction = WireDate.parseDay("2023-01-15")
    vm.intendedFiling = WireDate.parseDay("2026-02-01")
    return vm
}

final class LimitationRadarViewModelTests: XCTestCase {

    override func setUp() {
        super.setUp()
        HTTPStub.reset()
    }

    func testMissingDatesSayWhatIsMissingAndSendNothing() async {
        let fake = FakeRadar()
        await onMain {
            let vm = LimitationRadarViewModel(service: fake)
            await vm.run()
            XCTAssertEqual(vm.errorMessage, "Enter the date time began to run and the filing date.")
            vm.causeOfAction = WireDate.parseDay("2023-01-15")
            await vm.run()
            XCTAssertEqual(vm.errorMessage, "Enter the filing date.")
            vm.causeOfAction = nil
            vm.intendedFiling = WireDate.parseDay("2023-01-15")
            await vm.run()
            XCTAssertEqual(vm.errorMessage, "Enter the date time began to run.")
        }
        XCTAssertTrue(fake.requests.isEmpty)
    }

    func testRequestCarriesProfileAndDayKeys() async {
        let fake = FakeRadar()
        fake.answer = audit(overdue: 17)
        await onMain {
            let vm = ready(fake)
            vm.selectProfile("residuary")
            vm.mediationStart = WireDate.parseDay("2025-12-01")
            await vm.run()
            let request = vm.request
            XCTAssertEqual(request?.profile, "residuary")
            XCTAssertEqual(request?.causeOfAction, "2023-01-15")
            XCTAssertEqual(request?.intendedFiling, "2026-02-01")
            XCTAssertEqual(request?.mediationStart, "2025-12-01")
            XCTAssertNil(request?.mediationEnd)
            vm.selectProfile("no_such")
            XCTAssertEqual(vm.profileKey, LimitationProfile.defaultKey)
            vm.clear(.mediationStart)
            XCTAssertNil(vm.mediationStart)
        }
        XCTAssertEqual(fake.requests.count, 1)
    }

    func testAPickedDayKeepsItsDateInIndia() {
        // A day picked in the radar's IST date picker, at any hour of that day, is that day.
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = WireDate.india
        for hour in [0, 1, 12, 23] {
            let d = cal.date(from: DateComponents(year: 2026, month: 1, day: 15, hour: hour, minute: 30))!
            XCTAssertEqual(WireDate.dayKey(d), "2026-01-15")
        }
    }

    func testEncodedBodyOmitsEmptyOptionals() throws {
        let body = LimitationAuditRequest(
            profile: "declaration", causeOfAction: "2023-01-15", intendedFiling: "2026-02-01",
            mediationStart: "", mediationEnd: nil, userId: "42")
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(body)) as? [String: String])
        XCTAssertEqual(
            Set(json.keys), ["profile", "cause_of_action", "intended_filing", "userId"])
    }

    func testHeadlineBranches() async {
        let cases: [(LimitationAudit, String)] = [
            (audit(overdue: 36, adjusted: -24, relies: true),
             "36 days late without the exclusion · 24 days remaining with it"),
            (audit(overdue: 1), "1 day past the last day to file"),
            (audit(color: "emerald", overdue: 0), "0 days remaining"),
            (audit(color: "emerald", overdue: -1), "1 day remaining"),
            (audit(color: "emerald", overdue: -40), "40 days remaining"),
        ]
        for (answer, expected) in cases {
            let fake = FakeRadar()
            fake.answer = answer
            await onMain {
                let vm = ready(fake)
                await vm.run()
                XCTAssertEqual(vm.headline, expected)
            }
        }
    }

    func testMediationLineVariants() async {
        let m = { (a: Bool, b: Bool, c: Bool, d: Int) in
            LimitationAudit.Mediation(
                start: "2025-12-01", end: "2026-01-30", endAssumed: a, capped: b,
                beganAfterExpiry: c, excludedDays: d)
        }
        let cases: [(LimitationAudit.Mediation, String, String?)] = [
            (m(false, false, false, 60), "60 days (1 December 2025 to 30 January 2026)", "16 March 2026"),
            (m(true, false, false, 1), "1 day (1 December 2025 to 30 January 2026, end date assumed)", "16 March 2026"),
            (m(false, true, false, 151), "151 days (1 December 2025 to 30 January 2026, capped at five months)", "16 March 2026"),
            (m(false, false, true, 0), "None — it began after the period had expired", nil),
        ]
        for (mediation, text, adjusted) in cases {
            let fake = FakeRadar()
            fake.answer = audit(overdue: 36, adjusted: -24, relies: true, mediation: mediation)
            await onMain {
                let vm = ready(fake)
                XCTAssertNil(vm.mediationText)
                await vm.run()
                XCTAssertEqual(vm.mediationText, text)
                XCTAssertEqual(vm.adjustedText, adjusted)
                XCTAssertEqual(vm.lastDayText, "15 January 2026")
                XCTAssertEqual(vm.steps, ["one", "two"])
            }
        }
    }

    func testErrorsClearTheResultAndWordTheMessage() async {
        let fake = FakeRadar()
        fake.answer = audit(overdue: 17)
        await onMain {
            let vm = ready(fake)
            await vm.run()
            XCTAssertNotNil(vm.result)
            fake.error = APIError.server(status: 400, message: "The filing date is earlier than the cause of action. Check both dates.")
            await vm.run()
            XCTAssertNil(vm.result)
            XCTAssertEqual(vm.errorMessage, "The filing date is earlier than the cause of action. Check both dates.")
            fake.error = APIError.transport("The Internet connection appears to be offline.")
            await vm.run()
            XCTAssertEqual(vm.errorMessage, LimitationRadarViewModel.unreachableMessage)
            fake.error = nil
            await vm.run()
            XCTAssertNil(vm.errorMessage)
            XCTAssertNotNil(vm.result)
        }
    }

    func testASecondRunWhileOneIsInFlightIsIgnored() async {
        let fake = FakeRadar()
        fake.answer = audit(overdue: 17)
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        fake.gate = stream
        await onMain {
            let vm = ready(fake)
            let first = Task { @MainActor in await vm.run() }
            while !vm.isRunning { await Task.yield() }
            await vm.run()
            continuation.yield()
            await first.value
            XCTAssertFalse(vm.isRunning)
        }
        XCTAssertEqual(fake.requests.count, 1)
    }

    // MARK: - Service

    func testServiceSendsThePostAndReadsAnObjectEnvelope() async throws {
        let config = APIConfig(baseURL: URL(string: "https://example.test/api")!)
        let client = APIClient(config: config, session: HTTPStub.session())
        await client.setCredentials(Credentials(token: "tok", userID: 42))
        let service = LimitationRadarService(client: client)
        HTTPStub.always(.json(
            #"{"success":false,"error":{"code":"MISSING_ARGUMENT","message":"cause_of_action is required."}}"#,
            status: 400))
        let request = LimitationAuditRequest(
            profile: "residuary", causeOfAction: "2023-01-15", intendedFiling: "2026-02-01")
        do {
            _ = try await service.audit(request)
            XCTFail("a refusal must throw")
        } catch {
            XCTAssertEqual(
                error as? APIError, .server(status: 400, message: "cause_of_action is required."))
        }
        let sent = try XCTUnwrap(HTTPStub.lastRequest)
        XCTAssertEqual(sent.httpMethod, "POST")
        XCTAssertEqual(sent.url?.path, "/api/limitation-radar")
        let body = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try XCTUnwrap(sent.httpBody)) as? [String: String])
        XCTAssertEqual(body["userId"], "42")
        XCTAssertEqual(body["profile"], "residuary")

        HTTPStub.always(.json("<html>", status: 500))
        do {
            _ = try await service.audit(request)
            XCTFail("a refusal must throw")
        } catch {
            XCTAssertEqual(
                error as? APIError,
                .server(status: 500, message: "The audit service responded with HTTP 500."))
        }
    }
}
