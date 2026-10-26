import XCTest
@testable import EmperorCore

/// The usage meters, from the platform's `/billing/entitlements` response.
final class AccountUsageTests: XCTestCase {

    /// The shape the route returns for a metered account mid-month — trimmed of the pricing
    /// fields this client deliberately never reads.
    private static let metered = #"""
    {"success":true,"signedIn":true,"feeTier":"essential","planKey":"essential","planLabel":"Essential",
     "tier":"premium","expired":false,"cycle":"monthly",
     "limits":{"matters":-1,"storageGb":10,"documents":-1,"scannedPages":6000,"chatQueries":1000,"deepThinkingQueries":150,"support":"email"},
     "usage":{"period":"2026-10","resetsAt":"2026-10-31T18:30:00.000Z","chatQueries":812,"deepThinkingQueries":150,
              "scannedPages":120,"documents":44,"matters":7,"storageUsedBytes":2400000000,"storageAllowanceBytes":10000000000},
     "metered":true,"upgradable":true,"overageRates":{"chatQuery":2}}
    """#

    private func decode(_ json: String) throws -> AccountUsage {
        try JSONDecoder().decode(EntitlementsResponse.self, from: Data(json.utf8)).usageModel
    }

    private func meter(_ usage: AccountUsage, _ kind: AccountUsage.Meter.Kind) -> AccountUsage.Meter? {
        usage.meters.first { $0.kind == kind }
    }

    func testAMeteredAccountReadsAsItsAllowances() throws {
        let usage = try decode(Self.metered)
        XCTAssertEqual(usage.planLabel, "Essential")
        XCTAssertTrue(usage.isMetered)
        XCTAssertEqual(usage.renewsOn.map(WireDate.dayKey), "2026-11-01")

        let questions = try XCTUnwrap(meter(usage, .questions))
        XCTAssertEqual(questions.summary, "812 of 1,000")
        XCTAssertTrue(questions.isRunningLow)
        XCTAssertFalse(questions.isExhausted)

        let thinking = try XCTUnwrap(meter(usage, .deepThinking))
        XCTAssertTrue(thinking.isExhausted)
        XCTAssertNotNil(thinking.note, "a sub-allowance is said to be one")

        XCTAssertEqual(meter(usage, .storage)?.summary, "2.2 GB of 9.3 GB", "binary units, as the web")
    }

    /// `-1` is the platform's word for "no limit" (`planLimits.UNLIMITED`). Reading it as a limit
    /// of minus one would draw a meter that is always over.
    func testMinusOneMeansNoLimit() throws {
        let usage = try decode(Self.metered)
        XCTAssertNil(meter(usage, .documents), "shown only when capped")
        XCTAssertNil(meter(usage, .matters), "shown only when capped")
        let uncapped = AccountUsage.Meter(kind: .documents, used: 44, limit: nil)
        XCTAssertNil(uncapped.fraction)
        XCTAssertEqual(uncapped.summary, "44 · no limit")
    }

    /// Staff and demo accounts are not metered; the platform shows them usage without limits
    /// rather than limits they are not held to.
    func testAnUnmeteredAccountShowsNoLimits() throws {
        let usage = try decode(Self.metered.replacingOccurrences(
            of: #""metered":true"#, with: #""metered":false"#))
        XCTAssertFalse(usage.isMetered)
        XCTAssertEqual(usage.meters.map(\.kind), [.questions, .scannedPages, .storage])
        XCTAssertTrue(usage.meters.filter { $0.kind != .storage }.allSatisfy { $0.limit == nil })
        XCTAssertNotNil(meter(usage, .storage)?.limit, "the storage allowance is shown even unmetered")
    }

    /// A meter's state is said in words as well as drawn in colour, so it reaches VoiceOver and
    /// anyone who cannot tell the red from the amber — and only when there is something to say.
    func testAMetersStateIsSaidInWords() throws {
        let usage = try decode(Self.metered)
        XCTAssertEqual(meter(usage, .questions)?.statusLabel, "Running low", "812 of 1,000")
        XCTAssertEqual(meter(usage, .deepThinking)?.statusLabel, "Used up", "150 of 150")
        XCTAssertNil(meter(usage, .scannedPages)?.statusLabel, "120 of 6,000 is not worth a word")
        XCTAssertNil(meter(usage, .storage)?.statusLabel, "2.2 of 9.3 GB")

        // The edges: four-fifths is low, one short of the limit is still only low, and past the
        // limit — a server that let one through — is used up, never something odder.
        XCTAssertNil(AccountUsage.Meter(kind: .questions, used: 799, limit: 1000).statusLabel)
        XCTAssertEqual(
            AccountUsage.Meter(kind: .questions, used: 800, limit: 1000).statusLabel, "Running low")
        XCTAssertEqual(
            AccountUsage.Meter(kind: .questions, used: 999, limit: 1000).statusLabel, "Running low")
        XCTAssertEqual(
            AccountUsage.Meter(kind: .questions, used: 1001, limit: 1000).statusLabel, "Used up")
    }

    /// A field the route stops sending must not cost the screen.
    func testASparseResponseStillDecodes() throws {
        let usage = try decode(#"{"success":true,"metered":true}"#)
        XCTAssertTrue(usage.meters.isEmpty, "no usage in the answer, nothing to draw — as the web")
        XCTAssertNil(usage.renewsOn)
    }

    func testStorageReadsTheWayPeopleSayIt() {
        XCTAssertEqual(AccountUsage.bytes(850 * 1_048_576), "850 MB")
        XCTAssertEqual(AccountUsage.bytes(1_073_741_824), "1 GB")
        XCTAssertEqual(AccountUsage.bytes(50 * 1_073_741_824), "50 GB")
    }
}

@MainActor
private func loadedModel(_ usage: AccountUsage?, error: Error? = nil) async -> AccountUsageViewModel {
    let model = AccountUsageViewModel(service: FakeUsage(usage: usage, error: error))
    await model.load()
    return model
}

private struct FakeUsage: UsageProviding {
    var usage: AccountUsage?
    var error: Error?
    func usage() async throws -> AccountUsage {
        if let error { throw error }
        return usage!
    }
}

final class AccountUsageViewModelTests: XCTestCase {

    func testTheRenewalLineSaysWhatIsTrue() async {
        let renew = WireDate.parse("2026-10-31T18:30:00.000Z")
        func line(_ usage: AccountUsage) async -> String? {
            await loadedModel(usage).renewalLine
        }
        let ended = await line(AccountUsage(
            planLabel: nil, isMetered: true, hasExpired: true, renewsOn: renew, meters: []))
        let unmetered = await line(AccountUsage(
            planLabel: nil, isMetered: false, hasExpired: false, renewsOn: renew, meters: []))
        let metered = await line(AccountUsage(
            planLabel: "Essential", isMetered: true, hasExpired: false, renewsOn: renew, meters: []))
        XCTAssertEqual(ended, "This account's plan has ended.")
        XCTAssertEqual(unmetered, "No usage limits apply to this account.")
        XCTAssertEqual(metered, "Monthly allowances renew on 1 November.")
    }

    func testAFailedLoadIsAFailureNotAnEmptyScreen() async {
        let state = await loadedModel(nil, error: APIError.transport("The request timed out.")).state
        XCTAssertNotNil(state.failure)
    }
}
