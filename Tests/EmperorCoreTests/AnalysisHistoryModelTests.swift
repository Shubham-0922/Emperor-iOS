import XCTest
@testable import EmperorCore

@MainActor
private func onMainActor(_ body: @MainActor () async -> Void) async {
    await body()
}

private func summary(_ id: String, _ title: String = "", files: [String] = []) -> AnalysisRunSummary {
    AnalysisRunSummary(id: id, title: title, createdAt: "2026-10-20T09:30:00.000Z", fileNames: files)
}

final class AnalysisHistoryModelTests: XCTestCase {

    func testLoadsTheToolsRuns() async {
        let fake = FakeAnalysis()
        fake.histories = [.success([summary("a", "Arora"), summary("b", "Bakshi")])]
        await onMainActor {
            let h = AnalysisHistoryModel(kind: .docIndex, service: fake)
            XCTAssertEqual(h.status, .loading)
            XCTAssertEqual(h.buttonLabel, "History")
            await h.refresh()
            XCTAssertEqual(h.status, .ready)
            XCTAssertEqual(h.runs.map(\.id), ["a", "b"])
            XCTAssertEqual(h.buttonLabel, "History, 2 past runs")
            XCTAssertFalse(h.offersSearch)
        }
    }

    func testAStaleReplyIsDropped() async {
        let fake = FakeAnalysis()
        let (gate, release) = AsyncStream<Void>.makeStream()
        fake.histories = [.success([summary("old")]), .success([summary("new")])]
        fake.historyGates = [0: gate]
        await onMainActor {
            let h = AnalysisHistoryModel(kind: .docIndex, service: fake)
            let first = Task { await h.refresh() }
            while fake.historyCalls < 1 { await Task.yield() }
            await h.refresh()
            XCTAssertEqual(h.runs.map(\.id), ["new"])
            release.yield()
            release.finish()
            await first.value
            XCTAssertEqual(h.runs.map(\.id), ["new"], "the older reply landed last and was dropped")
        }
    }

    func testASilentRefreshThatFailsKeepsTheList() async {
        let fake = FakeAnalysis()
        fake.histories = [.success([summary("a")]), .failure(APIError.server(status: 503, message: "down"))]
        await onMainActor {
            let h = AnalysisHistoryModel(kind: .devilsAdvocate, service: fake)
            await h.refresh()
            await h.refresh(silent: true)
            XCTAssertEqual(h.status, .ready)
            XCTAssertEqual(h.runs.map(\.id), ["a"])
            await h.refresh()
            XCTAssertEqual(h.status, .failed("down"))
        }
    }

    func testRemoveTakesTheRunOffTheList() async {
        let fake = FakeAnalysis()
        fake.histories = [.success([summary("a"), summary("b")])]
        await onMainActor {
            let h = AnalysisHistoryModel(kind: .listOfDates, service: fake)
            await h.refresh()
            let removed = await h.remove("a")
            XCTAssertTrue(removed)
            XCTAssertEqual(h.runs.map(\.id), ["b"])
            fake.deleteError = APIError.server(status: 500, message: "Could not delete that run. Try again.")
            let failed = await h.remove("b")
            XCTAssertFalse(failed)
            XCTAssertEqual(h.runs.map(\.id), ["b"])
            XCTAssertEqual(h.openError, "Could not delete that run. Try again.")
        }
        XCTAssertEqual(fake.deleted, ["a"])
    }

    func testOpenFetchesTheRunOrSaysWhyNot() async {
        let fake = FakeAnalysis()
        fake.runs["a"] = AnalysisRun(summary: summary("a"), result: .object([:]))
        await onMainActor {
            let h = AnalysisHistoryModel(kind: .devilsAdvocate, service: fake)
            let run = await h.open("a")
            XCTAssertEqual(run?.id, "a")
            XCTAssertNil(h.opening)
            XCTAssertNil(h.openError)
            let missing = await h.open("zz")
            XCTAssertNil(missing)
            XCTAssertEqual(h.openError, "No such saved analysis.")
        }
    }

    func testSearchOffersItselfPastEightAndLooksAtTitlesAndFiles() async {
        let fake = FakeAnalysis()
        var runs = (1...8).map { summary("r\($0)", "Run \($0)") }
        runs.append(summary("n", "", files: ["Notice.pdf", "Reply.pdf"]))
        fake.histories = [.success(runs)]
        await onMainActor {
            let h = AnalysisHistoryModel(kind: .docIndex, service: fake)
            await h.refresh()
            XCTAssertTrue(h.offersSearch)
            h.query = " reply "
            XCTAssertEqual(h.filtered.map(\.id), ["n"])
            h.query = "run 3"
            XCTAssertEqual(h.filtered.map(\.id), ["r3"])
            XCTAssertEqual(summary("n", "", files: ["Notice.pdf"]).displayTitle, "Notice.pdf")
            XCTAssertEqual(summary("e").displayTitle, "Untitled run")
        }
    }
}
