import XCTest
@testable import EmperorCore

@MainActor
private func onMainActor(_ body: @MainActor () async throws -> Void) async rethrows {
    try await body()
}

private let plaint = ChatAttachment(name: "Plaint.pdf", folderName: "Bakshi")
private let order = ChatAttachment(name: "Interim_Order.pdf", folderName: "Bakshi/Orders")

private let reportResult: JSONValue = .object([
    "matter": .object(["title": .string("Bakshi v. State")]),
    "weakSpots": .array([.object(["id": .number(1), "severity": .string("serious"), "title": .string("Late notice")])]),
])

@MainActor
private func model(
    _ fake: FakeAnalysis, kind: AnalysisToolKind = .devilsAdvocate, clock: AnalysisClock = AnalysisClock(),
    pollInterval: Duration = .seconds(2)
) -> AnalysisRunModel {
    AnalysisRunModel(
        kind: kind, service: fake, history: AnalysisHistoryModel(kind: kind, service: fake),
        pollInterval: pollInterval, now: { clock.now }, sleep: clock.sleep, makeChatID: { "chat-1" })
}

final class AnalysisRunModelTests: XCTestCase {

    func testRunStartsOnTheChosenDocumentsAndPollsUntilDone() async {
        let fake = FakeAnalysis()
        fake.polls = [
            .success(AnalysisJob(status: "reading", stage: "Opening your documents", progress: 0.02)),
            .success(AnalysisJob(status: "thinking", stage: "Spotting every weak spot", progress: 0.4)),
            .success(AnalysisJob(status: "done", stage: "Done", progress: 1, result: reportResult)),
        ]
        let clock = AnalysisClock()
        await onMainActor {
            let vm = model(fake, clock: clock)
            XCTAssertFalse(vm.canRun)
            XCTAssertEqual(vm.ctaNote, "Choose at least one document to begin.")
            vm.setFiles([plaint, order])
            vm.reference = "We act for Bakshi."
            XCTAssertTrue(vm.canRun)
            XCTAssertEqual(vm.ctaNote, AnalysisToolKind.devilsAdvocate.ctaNote)
            let task = vm.run()
            if case .running(let stage, let progress, _) = vm.phase {
                XCTAssertEqual(stage, "Getting your documents ready…")
                XCTAssertEqual(progress, 0)
            } else {
                XCTFail("not running: \(vm.phase)")
            }
            await task?.value
            guard case .done(let outcome) = vm.phase else { return XCTFail("not done: \(vm.phase)") }
            XCTAssertEqual(outcome.fileNames, ["Plaint.pdf", "Interim_Order.pdf"])
            XCTAssertEqual(outcome.reference, "We act for Bakshi.")
            XCTAssertNil(outcome.fromHistory)
            guard case .devilsAdvocate(let report) = outcome.result else { return XCTFail("wrong result") }
            XCTAssertEqual(report.matter.title, "Bakshi v. State")
        }
        XCTAssertEqual(fake.starts.count, 1)
        XCTAssertEqual(fake.starts.first?.kind, .devilsAdvocate)
        XCTAssertEqual(fake.starts.first?.files, [plaint, order])
        XCTAssertEqual(fake.starts.first?.chatID, "chat-1")
        XCTAssertEqual(fake.pollCount, 3)
        XCTAssertEqual(clock.sleeps, [.seconds(2), .seconds(2)])
    }

    func testStageAndProgressFollowEachPoll() async {
        let fake = FakeAnalysis()
        fake.polls = [
            .success(AnalysisJob(status: "thinking", stage: "Spotting every date", progress: 0.4)),
            .success(AnalysisJob(status: "writing", stage: nil, progress: nil)),
        ]
        let clock = AnalysisClock()
        await onMainActor {
            let vm = model(fake, kind: .listOfDates, clock: clock)
            vm.setFiles([plaint])
            let task = vm.run()
            // Waits until the second poll has been read, then looks.
            while fake.pollCount < 3 { await Task.yield() }
            if case .running(let stage, let progress, _) = vm.phase {
                XCTAssertEqual(stage, "Spotting every date", "a poll without a stage keeps the last")
                XCTAssertEqual(progress, 0.4)
            } else {
                XCTFail("not running: \(vm.phase)")
            }
            vm.cancel()
            await task?.value
        }
    }

    func testAFailedJobIsAnErrorWithItsOwnWords() async {
        let fake = FakeAnalysis()
        fake.polls = [.success(AnalysisJob(status: "error", error: "This analysis would cost more than its limit of $2.00."))]
        await onMainActor {
            let vm = model(fake, kind: .docIndex)
            vm.setFiles([plaint])
            await vm.run()?.value
            guard case .failed(let failure) = vm.phase else { return XCTFail("not failed: \(vm.phase)") }
            XCTAssertEqual(failure.message, "This analysis would cost more than its limit of $2.00.")
            XCTAssertTrue(failure.canRetry)
            XCTAssertNil(failure.refusal)
            XCTAssertEqual(vm.failureMessage, failure.message, "only the report adds its reassurance")
        }
    }

    func testTheReportsFailureAddsItsReassurance() async {
        let fake = FakeAnalysis()
        fake.polls = [.success(AnalysisJob(status: "error", error: nil))]
        await onMainActor {
            let vm = model(fake)
            vm.setFiles([plaint])
            await vm.run()?.value
            XCTAssertEqual(vm.failureMessage, "The analysis failed. Try again. Your documents are safe; nothing was shared.")
        }
    }

    func testAPlanRefusalOffersNoRetry() async {
        let fake = FakeAnalysis()
        fake.startError = APIError.refused(Refusal(code: .queryLimit, status: 402, serverMessage: "used up"))
        await onMainActor {
            let vm = model(fake)
            vm.setFiles([plaint])
            await vm.run()?.value
            guard case .failed(let failure) = vm.phase else { return XCTFail("not failed") }
            XCTAssertEqual(failure.refusal?.code, .queryLimit)
            XCTAssertFalse(failure.canRetry)
            XCTAssertEqual(failure.message, "This account has used this month's questions.")
            XCTAssertEqual(vm.failureMessage, failure.message, "no reassurance on a plan refusal")
        }
        XCTAssertEqual(fake.pollCount, 0)
    }

    func testARunOverTwentyFiveMinutesIsGivenUp() async {
        let fake = FakeAnalysis()
        fake.polls = [.success(AnalysisJob(status: "thinking", stage: "Still thinking", progress: 0.5))]
        let clock = AnalysisClock()
        await onMainActor {
            let vm = model(fake, clock: clock, pollInterval: .seconds(600))
            vm.setFiles([plaint])
            await vm.run()?.value
            guard case .failed(let failure) = vm.phase else { return XCTFail("not failed") }
            XCTAssertEqual(failure.message, "This is taking too long. Try fewer or shorter documents.")
            XCTAssertTrue(failure.canRetry)
        }
        XCTAssertEqual(fake.pollCount, 4, "polled at 0, 10, 20 and 30 minutes")
    }

    func testCancelStopsPollingAndKeepsTheDocuments() async {
        let fake = FakeAnalysis()
        fake.polls = [.success(AnalysisJob(status: "thinking", progress: 0.3))]
        await onMainActor {
            let vm = model(fake)
            vm.setFiles([plaint])
            vm.reference = "note"
            let task = vm.run()
            while fake.pollCount < 2 { await Task.yield() }
            vm.cancel()
            await task?.value
            XCTAssertEqual(vm.phase, .intake)
            XCTAssertEqual(vm.files, [plaint])
            XCTAssertEqual(vm.reference, "note")
        }
        let after = fake.pollCount
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(fake.pollCount, after, "no poll after cancel")
    }

    func testAnUnreadableResultIsAnErrorNotABlankPage() async {
        let fake = FakeAnalysis()
        fake.polls = [.success(AnalysisJob(status: "done", result: .string("not a report")))]
        await onMainActor {
            let vm = model(fake, kind: .docIndex)
            vm.setFiles([plaint])
            await vm.run()?.value
            guard case .failed(let failure) = vm.phase else { return XCTFail("not failed") }
            XCTAssertEqual(failure.message, "The AI sent back an index we could not read. Please try again.")
            XCTAssertTrue(failure.canRetry)
        }
    }

    func testAFinishedRunWithARunIDRefreshesHistorySilently() async {
        let fake = FakeAnalysis()
        let saved = AnalysisRunSummary(id: "anr_1", title: "Bakshi v. State", createdAt: "2026-10-27T09:34:00.000Z")
        fake.histories = [.success([saved])]
        fake.polls = [.success(AnalysisJob(status: "done", result: reportResult, runId: "anr_1"))]
        await onMainActor {
            let vm = model(fake)
            vm.setFiles([plaint])
            await vm.run()?.value
            XCTAssertEqual(vm.history.runs, [saved])
            XCTAssertEqual(vm.history.status, .ready)
        }
        XCTAssertEqual(fake.historyCalls, 1)
    }

    func testARunWithoutARunIDLeavesHistoryAlone() async {
        let fake = FakeAnalysis()
        fake.polls = [.success(AnalysisJob(status: "done", result: reportResult, runId: nil))]
        await onMainActor {
            let vm = model(fake)
            vm.setFiles([plaint])
            await vm.run()?.value
        }
        XCTAssertEqual(fake.historyCalls, 0)
    }

    func testAStoredRunIsShownWithWhereItCameFrom() async {
        let fake = FakeAnalysis()
        let summary = AnalysisRunSummary(
            id: "anr_7", title: "Bakshi", createdAt: "2026-10-20T09:30:00.000Z",
            fileNames: ["Plaint.pdf"], reference: "We act for Bakshi.")
        await onMainActor {
            let vm = model(fake)
            vm.show(run: AnalysisRun(summary: summary, result: reportResult))
            guard case .done(let outcome) = vm.phase else { return XCTFail("not done") }
            XCTAssertEqual(outcome.fromHistory, summary)
            XCTAssertEqual(outcome.fileNames, ["Plaint.pdf"])
            XCTAssertEqual(outcome.reference, "We act for Bakshi.")
            XCTAssertEqual(outcome.madeOn, WireDate.parse("2026-10-20T09:30:00.000Z"))

            vm.show(run: AnalysisRun(summary: summary, result: nil))
            guard case .failed(let failure) = vm.phase else { return XCTFail("not failed") }
            XCTAssertEqual(failure.message, "This saved report could not be read.")
            XCTAssertEqual(failure.fromHistory, summary)
        }
    }

    func testRetryOfAnUnreadableStoredRunOpensItAgain() async {
        let fake = FakeAnalysis()
        let summary = AnalysisRunSummary(id: "anr_7", title: "Bakshi")
        fake.runs["anr_7"] = AnalysisRun(summary: summary, result: reportResult)
        await onMainActor {
            let vm = model(fake)
            vm.show(run: AnalysisRun(summary: summary, result: .string("junk")))
            await vm.retry()
            guard case .done = vm.phase else { return XCTFail("not reopened: \(vm.phase)") }
        }
        XCTAssertTrue(fake.starts.isEmpty, "a stored run is reopened, not run again")
    }

    func testStartOverClearsEverything() async {
        let fake = FakeAnalysis()
        await onMainActor {
            let vm = model(fake)
            vm.setFiles([plaint, ChatAttachment(name: "Loose.pdf", folderName: nil)])
            vm.reference = "x"
            XCTAssertEqual(vm.refusedFiles.count, 1)
            vm.startOver()
            XCTAssertTrue(vm.files.isEmpty)
            XCTAssertTrue(vm.refusedFiles.isEmpty)
            XCTAssertEqual(vm.reference, "")
            XCTAssertEqual(vm.phase, .intake)
        }
    }

    func testANoteOverTheLimitHoldsTheButton() async {
        let fake = FakeAnalysis()
        await onMainActor {
            let vm = model(fake)
            vm.setFiles([plaint])
            vm.reference = String(repeating: "a", count: 2001)
            XCTAssertFalse(vm.canRun)
            XCTAssertEqual(vm.ctaNote, "The note is too long (2,000 characters at most)")
            XCTAssertEqual(AnalysisInput.referenceCounter(vm.reference), "2,001 / 2,000")
        }
    }

    func testTheClockReadsMinutesAndSeconds() {
        XCTAssertEqual(AnalysisRunModel.clock(0), "0:00")
        XCTAssertEqual(AnalysisRunModel.clock(65), "1:05")
        XCTAssertEqual(AnalysisRunModel.clock(600), "10:00")
    }
}
