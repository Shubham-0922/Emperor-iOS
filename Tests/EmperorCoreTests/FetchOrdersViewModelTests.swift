import XCTest
@testable import EmperorCore

@MainActor
private func onMain(_ body: @MainActor () async throws -> Void) async rethrows {
    try await body()
}

@MainActor
private func makeModel(
    _ fake: FakeFetchOrders, matters: FakeMatterCreation = FakeMatterCreation(),
    store: InMemoryCacheStore = InMemoryCacheStore()
) -> FetchOrdersViewModel {
    FetchOrdersViewModel(
        service: fake, matters: matters, history: LookupHistory(store: store, userID: "7"),
        today: { "2026-10-12" })
}

final class FetchOrdersViewModelTests: XCTestCase {

    func testAReadCaseShowsItsRecordAndIsRemembered() async {
        let fake = FakeFetchOrders()
        let record = lookupRecord()
        fake.answers = [.success(LookupResult(record: record, cached: true))]
        await onMain {
            let vm = makeModel(fake)
            await vm.run(lookupCard())
            XCTAssertEqual(vm.phase, .record(lookupCard(), record, cached: true))
            XCTAssertEqual(vm.record, record)
            XCTAssertTrue(vm.cached)
            XCTAssertEqual(vm.recent.map(\.key), ["DLHC010000122025"])
            XCTAssertEqual(vm.recent.first?.title, "RAM KUMAR vs. STATE")
            XCTAssertEqual(vm.ctaTitle, "Add to Matters")
            XCTAssertNil(vm.matterID)
        }
    }

    func testAFailureIsShownAndOnlyARetryableOneIsRetried() async {
        let fake = FakeFetchOrders()
        fake.answers = [.failure(.notFound("No details."))]
        await onMain {
            let vm = makeModel(fake)
            await vm.run(lookupCard())
            XCTAssertEqual(vm.phase, .failed(lookupCard(), .notFound("No details.")))
            vm.retry()
            // Nothing was asked again.
            try? await Task.sleep(nanoseconds: 50_000_000)
            XCTAssertEqual(fake.cards.count, 1)
            XCTAssertTrue(vm.recent.isEmpty, "a failed lookup is not remembered")
        }
    }

    func testARetryableFailureCanBeTriedAgain() async {
        let fake = FakeFetchOrders()
        let record = lookupRecord()
        fake.answers = [.failure(.courtDown("Down.")), .success(LookupResult(record: record, cached: false))]
        await onMain {
            let vm = makeModel(fake)
            await vm.run(lookupCard())
            guard case .failed(_, let failure) = vm.phase else { return XCTFail("\(vm.phase)") }
            XCTAssertTrue(failure.retryable)
            await vm.run(lookupCard())
            XCTAssertEqual(vm.record, record)
            XCTAssertEqual(fake.cards.count, 2)
        }
    }

    func testAnExistingMatterTurnsTheOfferIntoOpen() async {
        let fake = FakeFetchOrders()
        fake.answers = [.success(LookupResult(record: lookupRecord(), cached: false))]
        let matters = FakeMatterCreation()
        matters.existing = "prj-9"
        await onMain {
            let vm = makeModel(fake, matters: matters)
            await vm.run(lookupCard())
            XCTAssertEqual(vm.matterID, "prj-9")
            XCTAssertEqual(vm.ctaTitle, "Open in Matters")
            XCTAssertEqual(vm.closingTitle, "This case is already in your Matters.")
        }
    }

    func testAddRequestCarriesTheRecordsTitleAndLeads() async throws {
        let fake = FakeFetchOrders()
        let record = lookupRecord(petitioners: ["RAM KUMAR", "SITA"], respondents: ["STATE OF DELHI"])
        fake.answers = [.success(LookupResult(record: record, cached: false))]
        try await onMain {
            let vm = makeModel(fake)
            XCTAssertNil(vm.addRequest(), "nothing to add before a record")
            await vm.run(lookupCard())
            let request = try XCTUnwrap(vm.addRequest())
            XCTAssertEqual(request.pick, lookupCard())
            XCTAssertEqual(request.caseTitle, "RAM KUMAR vs. STATE")
            XCTAssertEqual(request.name, LookupModel.titleOf(record.case))
            XCTAssertEqual(request.side, .skip)
            XCTAssertEqual(request.firstLead, "RAM KUMAR")
            XCTAssertEqual(request.secondLead, "STATE OF DELHI")
            vm.added(MatterCreated(projectID: "prj-2", existed: false))
            XCTAssertEqual(vm.matterID, "prj-2")
        }
    }

    func testRecentKeepsSixNewestFirstWithoutDuplicates() async {
        let fake = FakeFetchOrders()
        fake.answers = [.success(LookupResult(record: lookupRecord(), cached: false))]
        let store = InMemoryCacheStore()
        await onMain {
            let vm = makeModel(fake, store: store)
            for n in 1...7 {
                await vm.run(lookupCard(cnr: "CNR\(n)"))
            }
            await vm.run(lookupCard(cnr: "CNR4"))
            XCTAssertEqual(vm.recent.map(\.key), ["CNR4", "CNR7", "CNR6", "CNR5", "CNR3", "CNR2"])
            XCTAssertEqual(vm.shownRecent.count, 3)
            // Read back by the next screen, for the same account only.
            XCTAssertEqual(LookupHistory(store: store, userID: "7").entries.count, 6)
            XCTAssertTrue(LookupHistory(store: store, userID: "8").entries.isEmpty)
        }
    }

    func testARecentEntryIsLookedUpWithItsWholeCard() async {
        let fake = FakeFetchOrders()
        fake.answers = [.success(LookupResult(record: lookupRecord(), cached: false))]
        await onMain {
            let vm = makeModel(fake)
            var card = lookupCard()
            card.scrapeRef = .object(["cino": .string("X1")])
            await vm.run(card)
            let entry = vm.recent[0]
            XCTAssertEqual(entry.card, card, "the scrape reference survives the round trip")
            vm.open(entry)
            for _ in 0..<50 where fake.cards.count < 2 { try? await Task.sleep(nanoseconds: 10_000_000) }
            XCTAssertEqual(fake.cards.last, card)
        }
    }

    func testResetAbandonsALookupInFlight() async {
        let fake = FakeFetchOrders()
        fake.answers = [.success(LookupResult(record: lookupRecord(), cached: false))]
        fake.holds = true
        await onMain {
            let vm = makeModel(fake)
            vm.fetch(lookupCard())
            for _ in 0..<100 where !fake.isHolding { try? await Task.sleep(nanoseconds: 10_000_000) }
            XCTAssertEqual(vm.phase, .loading(lookupCard()))
            XCTAssertEqual(vm.loadingText, "Asking High Court — Delhi for W.P.(C) 12/2025…")
            vm.reset()
            fake.release()
            try? await Task.sleep(nanoseconds: 50_000_000)
            XCTAssertEqual(vm.phase, .search)
            XCTAssertTrue(vm.recent.isEmpty)
        }
    }

    func testOrdersFilterByYearAndShowEightAtFirst() async {
        let fake = FakeFetchOrders()
        var orders: [LookupRecord.Order] = []
        for n in 1...10 { orders.append(.init(date: "2025-01-\(n < 10 ? "0" : "")\(n)", title: "O\(n)")) }
        orders.append(.init(date: "2024-05-01", title: "Older"))
        fake.answers = [.success(LookupResult(record: lookupRecord(orders: orders), cached: false))]
        await onMain {
            let vm = makeModel(fake)
            await vm.run(lookupCard())
            XCTAssertEqual(vm.orderYears, ["2025", "2024"])
            XCTAssertEqual(vm.visibleOrders.count, 8)
            XCTAssertEqual(vm.ordersToggleTitle, "Show all 11")
            vm.showsAllOrders = true
            XCTAssertEqual(vm.visibleOrders.count, 11)
            XCTAssertEqual(vm.ordersToggleTitle, "Show fewer")
            vm.orderYear = "2024"
            XCTAssertFalse(vm.showsAllOrders, "a new year starts folded")
            XCTAssertEqual(vm.visibleOrders.map(\.title), ["Older"])
            XCTAssertNil(vm.ordersToggleTitle)
        }
    }
}

final class LookupFailureTests: XCTestCase {

    func testCodesAndStatusesClassify() {
        XCTAssertEqual(LookupFailure.from(code: "NOT_FOUND", status: 404, message: "m"), .notFound("m"))
        XCTAssertEqual(LookupFailure.from(code: "BAD_REQUEST", status: 400, message: "m"), .badRequest("m"))
        XCTAssertEqual(LookupFailure.from(code: "RATE_LIMIT", status: 429, message: "m"), .rateLimited("m"))
        XCTAssertEqual(LookupFailure.from(code: "COURT_DOWN", status: 502, message: "m"), .courtDown("m"))
        XCTAssertEqual(LookupFailure.from(code: "AUTH", status: 401, message: "m"), .auth("m"))
        XCTAssertEqual(LookupFailure.from(code: nil, status: 401, message: nil),
                       .auth("Please sign in again to fetch court records."))
        XCTAssertEqual(LookupFailure.from(code: nil, status: 500, message: "boom"), .other("boom"))
        XCTAssertEqual(LookupFailure.from(code: nil, status: 200, message: ""), .other(LookupFailure.fallbackMessage))
    }

    func testOnlyAMissingCaseOrABadCardIsFinal() {
        XCTAssertFalse(LookupFailure.notFound("").retryable)
        XCTAssertFalse(LookupFailure.badRequest("").retryable)
        XCTAssertTrue(LookupFailure.rateLimited("").retryable)
        XCTAssertTrue(LookupFailure.courtDown("").retryable)
        XCTAssertTrue(LookupFailure.auth("").retryable)
        XCTAssertTrue(LookupFailure.other("").retryable)
        XCTAssertEqual(LookupFailure.notFound("").title, "The court has nothing under that number.")
        XCTAssertEqual(LookupFailure.courtDown("").title, "We could not read this case just now.")
    }

    func testAnOrderOpensOnlyWhenItIsAWebAddress() {
        XCTAssertNotNil(LookupRecord.Order(url: "https://court.example/o.pdf").webURL)
        XCTAssertNotNil(LookupRecord.Order(url: "http://court.example/o.pdf").webURL)
        XCTAssertNil(LookupRecord.Order(url: "ejagriti-order:123").webURL)
        XCTAssertNil(LookupRecord.Order(url: "ejagriti:77").webURL)
        XCTAssertNil(LookupRecord.Order(url: "javascript:alert(1)").webURL)
        XCTAssertNil(LookupRecord.Order(url: nil).webURL)
    }
}
