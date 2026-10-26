import XCTest
@testable import EmperorCore

/// The Library's home, search, collections, Acts index, books and covers, driven with
/// `FakeLibrary`.
final class LibraryTests: XCTestCase {

    // MARK: - Home

    func testUnavailableCatalogueIsNotAFailure() async {
        await libraryRun { fake in
            fake.categoriesResult = .failure(LibraryError.catalogueUnavailable)
            let model = LibraryHomeViewModel(service: fake)
            await model.load()
            XCTAssertTrue(model.isUnavailable)
            XCTAssertNil(model.state.failure)
            XCTAssertEqual(LibraryHomeViewModel.unavailableMessage, "The catalogue has not been built on this server yet.")

            fake.categoriesResult = .failure(APIError.server(status: 500, message: "library_failed"))
            await model.load()
            XCTAssertFalse(model.isUnavailable)
            XCTAssertNotNil(model.state.failure, "any other failure is a failure, with Try again")
        }
    }

    func testShelvesFollowTheWebOrderAndLoadOnce() async {
        await libraryRun { fake in
            fake.categoriesResult = .success([
                LibraryCategory(key: "books-and-law-reports", count: 1),
                LibraryCategory(key: "case-law", count: 3),
                LibraryCategory(key: "bare-acts", count: 2),
                LibraryCategory(key: "something-new", count: 1),
            ])
            fake.shelves["case-law"] = [.sample(1), .sample(2)]
            let model = LibraryHomeViewModel(service: fake)
            await model.load()
            XCTAssertEqual(model.shelfKeys, ["bare-acts", "case-law", "books-and-law-reports"])
            XCTAssertEqual(model.orderedCategories.map(\.key).last, "something-new")
            await model.loadShelf("case-law")
            await model.loadShelf("case-law")
            XCTAssertEqual(fake.count("shelf:case-law"), 1)
            XCTAssertEqual(model.shelf("case-law").items.map(\.id), [1, 2])
            XCTAssertEqual(model.shelf("case-law").state, .loaded)
        }
    }

    func testAFailedShelfIsAskedAgain() async {
        await libraryRun { fake in
            fake.shelfError = APIError.server(status: 500, message: "x")
            let model = LibraryHomeViewModel(service: fake)
            await model.loadShelf("bare-acts")
            XCTAssertNotNil(model.shelf("bare-acts").state.failure)
            fake.shelfError = nil
            await model.loadShelf("bare-acts")
            XCTAssertEqual(model.shelf("bare-acts").state, .loaded)
            XCTAssertEqual(fake.count("shelf:bare-acts"), 2)
        }
    }

    func testSearchAsksTitlesAndPassagesAndSurvivesOneFailing() async {
        await libraryRun { fake in
            fake.titleSearchResult = .success(LibraryGroupedResults(groups: [
                .init(category: "case-law", label: "Case law", total: 3400, items: [.sample(1)]),
                .init(category: "bare-acts", label: "Bare acts", total: 12, items: [.sample(2, category: "bare-acts")]),
                .init(category: "tribunals", label: "Tribunals", total: 0, items: []),
            ]))
            fake.searchHandler = { _ in throw APIError.server(status: 503, message: "search_busy") }
            let model = LibraryHomeViewModel(service: fake)
            model.query = "  penal "
            await model.submitSearch()
            XCTAssertEqual(model.submittedQuery, "penal")
            XCTAssertEqual(fake.count("titleSearch"), 1)
            XCTAssertEqual(fake.count("search"), 1)
            XCTAssertEqual(fake.searchCalls.first?.category, "case-law")
            XCTAssertEqual(fake.searchCalls.first?.pageSize, 5)
            XCTAssertEqual(model.resultGroups.map(\.category), ["bare-acts", "case-law"], "shelf order, empty ones dropped")
            XCTAssertTrue(model.passagesFailed)
            XCTAssertFalse(model.searchFailed)
            XCTAssertFalse(model.foundNothing)
            XCTAssertEqual(LibraryHomeViewModel.resultTitle(for: model.resultGroups[1]), "Case law by name")
        }
    }

    func testSearchThatFindsNothingOrFailsEverywhere() async {
        await libraryRun { fake in
            let model = LibraryHomeViewModel(service: fake)
            model.query = "zzz"
            await model.submitSearch()
            XCTAssertTrue(model.foundNothing)
            XCTAssertEqual(model.nothingFoundTitle, "Nothing found for “zzz”")

            fake.titleSearchResult = .failure(APIError.transport("offline"))
            fake.searchHandler = { _ in throw APIError.transport("offline") }
            await model.submitSearch()
            XCTAssertTrue(model.searchFailed)
            XCTAssertFalse(model.foundNothing)

            fake.searchHandler = { _ in
                var page = LibraryPage(items: [.sample(9)], total: 1000)
                page.totalIsCapped = true
                return page
            }
            await model.submitSearch()
            XCTAssertEqual(model.passageCountText, "1,000+")
            model.query = ""
            await model.submitSearch()
            XCTAssertFalse(model.isShowingResults)
        }
    }

    // MARK: - Collections

    private static func pages(total: Int = 45) -> (LibraryFilters) throws -> LibraryPage {
        { f in
            let page = f.page ?? 1
            let size = f.pageSize ?? 20
            let first = (page - 1) * size
            let items = (first..<min(total, first + size)).map { LibraryDoc.sample($0 + 1) }
            var out = LibraryPage(items: items, total: total, page: page, pageSize: size)
            out.sort = f.sort
            return out
        }
    }

    func testCaseLawPagesThroughThreePages() async {
        await libraryRun { fake in
            fake.browseHandler = Self.pages()
            let model = LibraryCollectionViewModel(category: LibraryCategory(key: "case-law"), service: fake)
            await model.load()
            XCTAssertEqual(model.pageLabel, "Page 1 of 3")
            XCTAssertEqual(fake.browseCalls.last?.sort, "date_desc", "Case Law is a chronology")
            XCTAssertEqual(fake.browseCalls.last?.pageSize, 20)
            XCTAssertFalse(model.canGoBack)
            await model.nextPage()
            await model.nextPage()
            XCTAssertEqual(model.pageLabel, "Page 3 of 3")
            XCTAssertFalse(model.canGoForward)
            XCTAssertEqual(model.items.count, 5)
            await model.nextPage()
            XCTAssertEqual(fake.browseCalls.count, 3, "no page past the last")
            XCTAssertEqual(model.countLine, "45 judgments")
        }
    }

    func testAPageBeingReplacedStaysOnScreen() async {
        await libraryRun { fake in
            fake.browseHandler = Self.pages()
            let model = LibraryCollectionViewModel(category: LibraryCategory(key: "case-law"), service: fake)
            await model.load()
            let gate = LibraryGate()
            fake.gate = { _ in await gate.wait() }
            let task = Task { @MainActor in await model.nextPage() }
            await libraryUntil { fake.browseCalls.count == 2 }
            XCTAssertTrue(model.isStale)
            XCTAssertEqual(model.items.first?.id, 1, "the old page is kept while the next loads")
            gate.open()
            await task.value
            XCTAssertFalse(model.isStale)
            XCTAssertEqual(model.items.first?.id, 21)
        }
    }

    func testALateAnswerForOldFiltersIsDropped() async {
        await libraryRun { fake in
            fake.browseHandler = { f in LibraryPage(items: [.sample(f.court == "delhi" ? 100 : 200)], total: 1) }
            let model = LibraryCollectionViewModel(category: LibraryCategory(key: "case-law"), service: fake)
            let gate = LibraryGate()
            fake.gate = { f in if f.court == "delhi" { await gate.wait() } }
            let slow = Task { @MainActor in await model.setCourt("delhi") }
            await libraryUntil { fake.browseCalls.count == 1 }
            await model.setCourt("bombay")
            XCTAssertEqual(model.items.map(\.id), [200])
            gate.open()
            await slow.value
            XCTAssertEqual(model.items.map(\.id), [200], "the slower, older answer does not overwrite the newer one")
        }
    }

    func testSwitchingCollectionKeepsTheSearchAndDropsTheFilters() async {
        await libraryRun { fake in
            let model = LibraryCollectionViewModel(category: LibraryCategory(key: "case-law"), query: "bail", service: fake)
            await model.setCourt("delhi")
            await model.setYears(from: 2015, to: 2020)
            XCTAssertEqual(model.activeFilterCount, 2)
            XCTAssertEqual(model.activeFilters.map(\.label), ["Delhi HC", "2015–2020"])
            await model.switchCategory(to: LibraryCategory(key: "tribunals"))
            XCTAssertEqual(model.query, "bail")
            XCTAssertEqual(model.activeFilterCount, 0)
            XCTAssertEqual(fake.browseCalls.last?.q, "bail")
            XCTAssertNil(fake.browseCalls.last?.court)
            XCTAssertEqual(fake.browseCalls.last?.category, "tribunals")
            XCTAssertEqual(fake.browseCalls.last?.sort, "year_desc", "the web's default for tribunals")
        }
    }

    func testWordsInsideIsOnlyForCaseLawWithASearch() async {
        await libraryRun { fake in
            let plain = LibraryCollectionViewModel(category: LibraryCategory(key: "case-law"), service: fake)
            await plain.setMode(.text)
            XCTAssertEqual(plain.effectiveMode, .titles)
            XCTAssertEqual(fake.count("search"), 0)

            let other = LibraryCollectionViewModel(category: LibraryCategory(key: "regulator-orders"), query: "kyc", service: fake)
            await other.setMode(.text)
            XCTAssertEqual(other.effectiveMode, .titles)
            XCTAssertEqual(fake.count("search"), 0)

            let caseLaw = LibraryCollectionViewModel(category: LibraryCategory(key: "case-law"), query: "bail", service: fake)
            await caseLaw.setMode(.text)
            XCTAssertEqual(caseLaw.effectiveMode, .text)
            XCTAssertEqual(fake.count("search"), 1)
            XCTAssertNil(fake.searchCalls.last?.sort, "best match by default")
            XCTAssertEqual(caseLaw.sortOptions.first?.label, "Best match")
            XCTAssertEqual(caseLaw.emptyTitle, "No judgments contain “bail”")
        }
    }

    func testUnclearDatesGoToTheEndOfANewestPage() async {
        await libraryRun { fake in
            var odd = LibraryDoc.sample(2, decidedOn: "2099-01-01")
            odd.category = "case-law"
            var flagged = LibraryDoc.sample(3, decidedOn: "2001-01-01")
            flagged.anomalies = [LibraryAnomaly(kind: "future_date")]
            fake.browseHandler = { _ in LibraryPage(items: [odd, flagged, .sample(1, decidedOn: "2020-01-01")], total: 3) }
            let model = LibraryCollectionViewModel(category: LibraryCategory(key: "case-law"), service: fake,
                                                   today: { "2026-10-27" })
            await model.load()
            XCTAssertEqual(model.items.map(\.id), [1, 2, 3])
            XCTAssertTrue(model.isDateUnclear(odd))
            await model.setSort("date_asc")
            XCTAssertEqual(model.items.map(\.id), [2, 3, 1], "only the newest list moves them")
        }
    }

    func testFacetRowsAndLetters() async {
        await libraryRun { fake in
            var facets = LibraryFacets()
            facets.yearRange = LibraryYearRange(min: 1990, max: 2025)
            facets.sorts = [LibrarySortOption(value: "title_asc", label: "Title A–Z")]
            fake.facetsByCategory["professional-institutes"] = facets
            let model = LibraryCollectionViewModel(category: LibraryCategory(key: "professional-institutes"), service: fake)
            await model.load()
            XCTAssertEqual(model.facetRows, [.publishers, .letters])
            XCTAssertEqual(model.rowLabel(.publishers), "Institute")
            XCTAssertFalse(model.showsList)
            XCTAssertEqual(model.pageSize, 36)
            await model.setLetter("B")
            XCTAssertEqual(fake.browseCalls.last?.letter, "B")
            XCTAssertEqual(fake.browseCalls.last?.sort, "title_asc", "a letter sorts A–Z")
            await model.setYears(from: 2000, to: nil)
            XCTAssertEqual(model.yearText, "2000–2025")
            await model.clearFilters()
            XCTAssertEqual(model.activeFilterCount, 0)
        }
    }

    // MARK: - Acts index

    func testActIndexSearchesEverythingAndDescribesTheCount() async {
        await libraryRun { fake in
            fake.actIndexHandler = { q in
                if q.kind == "featured" { return LibraryActIndexPage(items: [.sample(1, category: "bare-acts")], total: 1) }
                return LibraryActIndexPage(items: [.sample(2478, category: "bare-acts")], total: 83)
            }
            let model = LibraryActIndexViewModel(service: fake)
            await model.load()
            XCTAssertTrue(model.isBrowsing)
            XCTAssertEqual(model.featured.map(\.id), [1])
            XCTAssertNil(fake.actIndexCalls.first { $0.kind != "featured" }?.kind, "browsing shows Acts")
            await model.setJurisdiction("Central")
            await model.setLetter("I")
            await model.setHas("rules")
            XCTAssertEqual(model.countLine, "83 Central Acts under I, with rules")
            await model.search("pmla")
            XCTAssertEqual(fake.actIndexCalls.last?.kind, "all")
            XCTAssertNil(fake.actIndexCalls.last?.letter, "a search clears the letter")
            XCTAssertEqual(fake.actIndexCalls.last?.pageSize, 60)
            XCTAssertFalse(model.isBrowsing)
            var act = LibraryDoc.sample(5, category: "bare-acts")
            act.tabCounts = ["amendments": 25, "rules": 9, "editions": 2]
            XCTAssertEqual(model.holds(act), "9 rules · 25 amendments", "the chosen Contains leads")
        }
    }

    // MARK: - Books

    func testASeriesIsReadInThreePagesAndGroupedByDecade() async {
        await libraryRun { fake in
            fake.browseHandler = { f in
                let page = f.page ?? 1
                var items: [LibraryDoc] = []
                for i in 0..<(page < 3 ? 100 : 20) {
                    var d = LibraryDoc(id: page * 1000 + i, title: "Volume \(i)", category: "books-and-law-reports")
                    d.year = 1900 + (page * 100 + i) % 90
                    items.append(d)
                }
                return LibraryPage(items: items, total: 320, page: page, pageSize: 100)
            }
            let model = LibrarySeriesViewModel(series: "ALL INDIA REPORTER", service: fake)
            await model.load()
            XCTAssertEqual(model.title, "All India Reporter")
            XCTAssertEqual(fake.browseCalls.map { $0.page ?? 1 }, [1, 2, 3])
            XCTAssertEqual(fake.browseCalls.first?.series, "ALL INDIA REPORTER")
            XCTAssertEqual(fake.browseCalls.first?.sort, "year_asc")
            XCTAssertEqual(model.volumes.count, 220)
            XCTAssertFalse(model.decades.isEmpty)
            XCTAssertTrue(model.summary.hasPrefix("320 volumes"))
        }
    }

    // MARK: - Covers

    func testCoversAskOnlyWhenWorthItAndRetryWhilePending() async {
        let fake = FakeLibrary()
        let loader = LibraryCoverLoader(service: fake, retryDelays: [0, 0])
        var none = LibraryDoc.sample(1, category: "books-and-law-reports")
        none.cover = "none"
        let none1 = await loader.image(for: none, width: 160)
        XCTAssertNil(none1)
        let text = await loader.image(for: .sample(2, ext: ".txt"), width: 160)
        XCTAssertNil(text)
        XCTAssertTrue(fake.coverCalls.isEmpty, "cover: none and a text document never ask")

        fake.coverResults[4] = [.pending(retryAfter: 5), .image(Data([1, 2]))]
        let image = await loader.image(for: .sample(4), width: 320)
        XCTAssertEqual(image, Data([1, 2]))
        XCTAssertEqual(fake.coverCalls.map(\.attempt), [0, 1])
        let again = await loader.image(for: .sample(4), width: 320)
        XCTAssertEqual(again, Data([1, 2]))
        XCTAssertEqual(fake.coverCalls.count, 2, "cached")

        fake.coverResults[5] = [.none]
        _ = await loader.image(for: .sample(5), width: 160)
        _ = await loader.image(for: .sample(5), width: 320)
        XCTAssertEqual(fake.coverCalls.filter { $0.id == 5 }.count, 1, "no cover is remembered")

        fake.coverResults[6] = [.pending(retryAfter: 1), .pending(retryAfter: 1), .pending(retryAfter: 1), .image(Data([9]))]
        let gaveUp = await loader.image(for: .sample(6), width: 160)
        XCTAssertNil(gaveUp, "pending three times: the typographic cover stays")
        XCTAssertEqual(fake.coverCalls.filter { $0.id == 6 }.count, 3)
    }
}

// MARK: - Helpers

@MainActor
func libraryRun(_ body: @MainActor (FakeLibrary) async -> Void) async {
    await body(FakeLibrary())
}

/// Waits (briefly) until a condition holds — for a request a task has started but not finished.
@MainActor
func libraryUntil(_ condition: @MainActor () -> Bool) async {
    for _ in 0..<500 where !condition() {
        try? await Task.sleep(nanoseconds: 2_000_000)
    }
}

/// Holds an answer back until opened.
final class LibraryGate: @unchecked Sendable {
    private let lock = NSLock()
    private var isOpen = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            let resume = lock.withLock { () -> Bool in
                if isOpen { return true }
                waiting.append(c)
                return false
            }
            if resume { c.resume() }
        }
    }

    func open() {
        let all = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            isOpen = true
            defer { waiting = [] }
            return waiting
        }
        all.forEach { $0.resume() }
    }
}
