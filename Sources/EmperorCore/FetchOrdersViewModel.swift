import Foundation
#if canImport(Darwin)
import Observation
#endif

/// Fetch Orders — look a court case up and read all of it without adding it anywhere
/// (the web's `src/pages/FetchOrders.jsx`):
///
/// - search: the court search every other screen uses, whose result is "Fetch this case";
/// - loading: the court's own website answers (nothing is saved);
/// - the record: orders, hearings, parties, timeline (`LookupDossierView`);
/// - keep it: Add to Matters, or Open in Matters when the case already is one.
///
/// See `ChatViewModel` for why `@Observable` is Apple-only.
#if canImport(Darwin)
@Observable
#endif
@MainActor
final class FetchOrdersViewModel {

    enum Phase: Equatable {
        case search
        case loading(CourtSearchResult)
        case failed(CourtSearchResult, LookupFailure)
        case record(CourtSearchResult, LookupRecord, cached: Bool)
    }

    private(set) var phase: Phase = .search
    /// The cases looked up lately, newest first (at most six; the screen shows three).
    private(set) var recent: [LookupHistory.Entry] = []
    /// The user's matter for the case on screen, when there is one: the offer becomes
    /// "Open in Matters".
    private(set) var matterID: String?
    /// The order-year chip chosen; "" is All.
    var orderYear = "" { didSet { if orderYear != oldValue { showsAllOrders = false } } }
    var showsAllOrders = false

    private let service: any FetchOrdersProviding
    private let matters: any MatterCreating
    private let history: LookupHistory
    private let today: @Sendable () -> String

    #if canImport(Darwin)
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    #else
    private var task: Task<Void, Never>?
    private var generation = 0
    #endif

    init(service: any FetchOrdersProviding, matters: any MatterCreating, history: LookupHistory,
         today: @escaping @Sendable () -> String = { WireDate.todayKey() }) {
        self.service = service
        self.matters = matters
        self.history = history
        self.today = today
        self.recent = history.entries
    }

    /// The "Looked up recently" rows.
    var shownRecent: [LookupHistory.Entry] { Array(recent.prefix(LookupHistory.shown)) }

    /// India's day now, for the dossier's "in 3 days" and "Upcoming".
    var todayKey: String { today() }

    // MARK: - Intents

    /// "Fetch this case" on a search result.
    func fetch(_ result: CourtSearchResult) {
        start(result)
    }

    /// A "Looked up recently" row.
    func open(_ entry: LookupHistory.Entry) {
        start(entry.card)
    }

    /// "Try again" — only for a failure worth another try. Never automatic: each fresh lookup
    /// counts against a per-minute allowance.
    func retry() {
        guard case .failed(let card, let failure) = phase, failure.retryable else { return }
        start(card)
    }

    /// "Search again" / "Look up another case": back to the search, abandoning any wait.
    func reset() {
        cancel()
        phase = .search
        matterID = nil
    }

    /// Abandons a lookup in progress (the screen closed). Nothing has been written anywhere.
    func cancel() {
        generation += 1
        task?.cancel()
        task = nil
        if case .loading = phase { phase = .search }
    }

    private func start(_ card: CourtSearchResult) {
        task?.cancel()
        task = Task { await run(card) }
    }

    /// Reads the case. Public so tests can await it.
    func run(_ card: CourtSearchResult) async {
        generation += 1
        let ticket = generation
        phase = .loading(card)
        matterID = nil
        orderYear = ""
        showsAllOrders = false
        do {
            let result = try await service.lookup(card)
            guard ticket == generation else { return }
            recent = history.remember(card, title: result.record.case.title)
            phase = .record(card, result.record, cached: result.cached)
            let found = await matters.existingMatter(for: card)
            guard ticket == generation else { return }
            matterID = found
        } catch is CancellationError {
            return
        } catch let failure as LookupFailure {
            guard ticket == generation else { return }
            phase = .failed(card, failure)
        } catch {
            guard ticket == generation else { return }
            phase = .failed(card, .other(DisplayText.message(for: error)))
        }
    }

    // MARK: - The record

    var record: LookupRecord? {
        if case .record(_, let record, _) = phase { return record }
        return nil
    }

    var card: CourtSearchResult? {
        switch phase {
        case .search: return nil
        case .loading(let card), .failed(let card, _), .record(let card, _, _): return card
        }
    }

    var cached: Bool {
        if case .record(_, _, let cached) = phase { return cached }
        return false
    }

    /// "Asking Supreme Court of India for SLP(C) 1234/2025…".
    var loadingText: String {
        guard let card else { return "" }
        let court = (card.courtName?.isEmpty == false) ? card.courtName! : "the court"
        let number = MatterMeta.lookupCaseNumber(
            caseType: card.caseType, caseNumber: card.caseNumber, caseYear: card.caseYear)
        let what = number.isEmpty ? "this case" : number
        return "Asking \(court) for \(what)…"
    }

    /// The offer in the header and at the foot.
    var ctaTitle: String { matterID == nil ? Copy.add : Copy.open }

    /// The closing band's heading.
    var closingTitle: String {
        matterID == nil ? "Want to keep an eye on this case?" : "This case is already in your Matters."
    }

    /// The years the orders span, for the chips (shown only when more than one).
    var orderYears: [String] { LookupModel.yearsOf(record?.orders ?? []) }

    /// The orders under the chosen year.
    var filteredOrders: [LookupRecord.Order] {
        LookupModel.orders(record?.orders ?? [], inYear: orderYear)
    }

    /// The order rows on screen: eight, or every one after "Show all".
    var visibleOrders: [LookupRecord.Order] {
        let list = filteredOrders
        return showsAllOrders ? list : Array(list.prefix(Self.ordersShown))
    }

    /// "Show all 12" / "Show fewer", or nil when everything already shows.
    var ordersToggleTitle: String? {
        let count = filteredOrders.count
        guard count > Self.ordersShown else { return nil }
        return showsAllOrders ? "Show fewer" : "Show all \(count)"
    }

    static let ordersShown = 8

    /// What Add to Matters starts with: the record's title as the name, no side yet, and each
    /// side's lead party for the side options.
    func addRequest() -> AddToMattersRequest? {
        guard case .record(let card, let record, _) = phase else { return nil }
        let c = record.case
        let recordTitle = (c.title?.isEmpty == false) ? c.title! : LookupModel.titleOf(c)
        return AddToMattersRequest(
            pick: card, caseTitle: recordTitle, name: LookupModel.titleOf(c), side: .skip,
            firstLead: record.parties.petitioners.first, secondLead: record.parties.respondents.first)
    }

    /// The matter made or found by Add to Matters: from now on the offer is to open it.
    func added(_ made: MatterCreated) {
        matterID = made.projectID
    }

    enum Copy {
        static let title = "Fetch Orders"
        static let headline = "Read any court case, in one place."
        static let blurb = "Orders, hearing history, parties and advocates — straight from the court’s own records, "
            + "without opening a single court website or adding the case to your dashboard."
        static let pickLabel = "Fetch this case"
        static let add = "Add to Matters"
        static let open = "Open in Matters"
        static let tryAgain = "Try again"
        static let searchAgain = "Search again"
        static let another = "Look up another case"
        static let copySummary = "Copy summary"
        static let copied = "Summary copied"
        static let recentTitle = "Looked up recently"
        static let slow = "Court websites can be slow. This usually takes under 20 seconds, and nothing is saved "
            + "to your account."
        static let steps: [(title: String, text: String, symbol: String)] = [
            ("Search", "Pick the court, type the case number or diary number.", "magnifyingglass"),
            ("Read", "Every order, hearing, party and advocate on one page. Nothing is saved.", "book"),
            ("Keep it, if you want", "Add it to Matters for hourly tracking and alerts. Or just close the page.",
             "folder.badge.plus"),
        ]
        static let keepPoints = [
            "Alerts when a new order or date appears",
            "Checked against the court every hour",
            "Files, tasks, fees and notes in one place",
        ]
    }
}
