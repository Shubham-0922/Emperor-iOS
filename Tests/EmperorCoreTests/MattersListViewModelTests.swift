import XCTest
@testable import EmperorCore

/// Noon in India on 12 Oct 2026 — every "today" in these tests.
private let noonIST: Date = ISO8601DateFormatter().date(from: "2026-10-12T06:30:00Z")!

private func matter(
    _ id: String, name: String, status: String? = "active", area: String? = nil,
    hearing: String? = nil, updated: String? = "2026-01-01T00:00:00.000Z", linked: String? = nil,
    created: String? = "2025-01-01T00:00:00.000Z", client: String? = nil, other: String? = nil,
    caseType: String? = nil, number: String? = nil, year: String? = nil, cnr: String? = nil,
    lastActivity: String? = nil
) -> Project {
    Project(
        id: id, name: name, client: client, caseNumber: number, caseYear: year, caseType: caseType,
        cnr: cnr, status: status, nextHearingDateRaw: hearing, linkedCaseID: linked,
        updatedAtRaw: updated, createdAtRaw: created, practiceArea: area, oppositeParty: other,
        lastActivityRaw: lastActivity)
}

@MainActor
private func withList(
    _ projects: [Project],
    _ body: @MainActor (FakeProjects, MattersListViewModel) async -> Void
) async {
    let fake = FakeProjects()
    fake.list = projects
    let model = MattersListViewModel(service: fake, now: { noonIST })
    await model.load()
    await body(fake, model)
}

final class MattersListViewModelTests: XCTestCase {

    /// Archived matters are always fetched: an archived matter still owns its linked case.
    func testTheListAlwaysAsksForArchivedMatters() async {
        await withList([]) { fake, _ in
            XCTAssertEqual(fake.archivedRequests, [true])
        }
    }

    /// Active is the default scope; the counts cover every status and an unknown status counts
    /// as active.
    func testStatusScopesAndCounts() async {
        await withList([
            matter("a", name: "A"), matter("b", name: "B", status: "archived"),
            matter("c", name: "C", status: "on_hold"), matter("d", name: "D", status: "weird"),
        ]) { _, model in
            XCTAssertEqual(model.status, .active)
            XCTAssertEqual(Set(model.visible.map(\.id)), ["a", "d"])
            XCTAssertEqual(model.counts[.active], 2)
            XCTAssertEqual(model.counts[.archived], 1)
            XCTAssertEqual(model.counts[.all], 4)
            XCTAssertEqual(model.statusLabel(.active), "Active · 2")
            XCTAssertEqual(model.statusLabel(.all), "All statuses · 4")
            XCTAssertEqual(model.summary, "2 active matters")

            model.status = .archived
            XCTAssertEqual(model.visible.map(\.id), ["b"])
            XCTAssertEqual(model.summary, "1 archived matter")
            model.status = .onHold
            XCTAssertEqual(model.summary, "1 matter on hold")
            model.status = .all
            XCTAssertEqual(model.visible.count, 4)
        }
    }

    /// The case-number search matches however the number is written: "wpc4412" finds
    /// "W.P.(C) 4412/2025".
    func testTheSearchSquashesCaseNumbers() async {
        await withList([
            matter("a", name: "Bhalla v. State", caseType: "W.P.(C)", number: "4412", year: "2025"),
            matter("b", name: "Other", client: "Kapoor Textiles", other: "Customs"),
        ]) { _, model in
            model.query = "wpc4412"
            XCTAssertEqual(model.visible.map(\.id), ["a"])
            model.query = "W.P.(C) 4412"
            XCTAssertEqual(model.visible.map(\.id), ["a"])
            model.query = "customs"
            XCTAssertEqual(model.visible.map(\.id), ["b"])
            model.query = "kapoor"
            XCTAssertEqual(model.visible.map(\.id), ["b"])
            XCTAssertEqual(model.summary, "1 of 2 active matters")
            // One character is too little to match squashed.
            model.query = "4"
            XCTAssertEqual(model.visible.map(\.id), ["a"])
        }
    }

    /// Only the areas present, in the vocabulary's order, then "No practice area"; the chosen
    /// one stays listed after its last matter has gone.
    func testPracticeAreaOptionsAndFilter() async {
        await withList([
            matter("a", name: "A", area: "writ"), matter("b", name: "B", area: "civil"),
            matter("c", name: "C"), matter("d", name: "D", area: "space-law"),
        ]) { _, model in
            XCTAssertEqual(model.areaOptions.map(\.label),
                           ["All practice areas", "Civil", "Writ / constitutional", "space-law", "No practice area"])
            model.area = "writ"
            XCTAssertEqual(model.visible.map(\.id), ["a"])
            model.area = MattersListViewModel.noArea
            XCTAssertEqual(model.visible.map(\.id), ["c"])
            model.area = "tax"
            XCTAssertEqual(model.areaOptions.last?.label, "Tax")
            XCTAssertTrue(model.visible.isEmpty)
            XCTAssertEqual(model.noMatches?.title, "No active matter in that practice area")
            XCTAssertEqual(model.noMatches?.clearTitle, "Clear search and filters")
            XCTAssertEqual(model.noMatches?.showAllTitle, "Show all statuses")
            model.clearFilters()
            XCTAssertEqual(model.visible.count, 4)
        }
    }

    /// Recent activity is the default order: the latest of updated, created and a last activity
    /// not in the future; ties by name.
    func testRecentActivityOrder() async {
        await withList([
            matter("old", name: "Old", updated: "2026-01-01T00:00:00.000Z"),
            matter("new", name: "New", updated: "2026-10-01T00:00:00.000Z"),
            matter("active", name: "Active", updated: "2026-02-01T00:00:00.000Z", lastActivity: "2026-10-05"),
            matter("future", name: "Future", updated: "2026-03-01T00:00:00.000Z", lastActivity: "2999-01-01"),
        ]) { _, model in
            XCTAssertEqual(model.visible.map(\.id), ["active", "new", "future", "old"])
        }
    }

    /// Next hearing: upcoming soonest first, then past (most recent first), then undated.
    func testHearingOrderAndTheWeeksCount() async {
        await withList([
            matter("none", name: "None"),
            matter("past", name: "Past", hearing: "2026-10-01"),
            matter("far", name: "Far", hearing: "2026-12-01"),
            matter("soon", name: "Soon", hearing: "2026-10-14"),
            matter("today", name: "Today", hearing: "2026-10-12"),
            matter("arch", name: "Arch", status: "archived", hearing: "2026-10-13"),
        ]) { _, model in
            model.sort = .hearing
            XCTAssertEqual(model.visible.map(\.id), ["today", "soon", "far", "past", "none"])
            XCTAssertEqual(model.hearingsThisWeek, 2)
            XCTAssertEqual(model.hearingsThisWeekText, "2 hearings in the next 7 days")
        }
    }

    /// Name A–Z ignores case and reads numbers by value.
    func testNameOrderIsNatural() async {
        await withList([
            matter("10", name: "Case 10"), matter("2", name: "case 2"), matter("b", name: "Bakshi"),
        ]) { _, model in
            model.sort = .name
            XCTAssertEqual(model.visible.map(\.id), ["b", "2", "10"])
        }
    }

    /// Every linked case, archived matters included, is left off the docket.
    func testLinkedCaseIDsIncludeArchivedMatters() async {
        await withList([
            matter("a", name: "A", linked: "case-1"),
            matter("b", name: "B", status: "archived", linked: "case-2"),
            matter("c", name: "C", linked: ""),
        ]) { _, model in
            XCTAssertEqual(model.linkedCaseIDs, ["case-1", "case-2"])
        }
    }

    /// A failed refresh keeps the rows on screen.
    func testAFailedRefreshKeepsTheRows() async {
        await withList([matter("a", name: "A")]) { fake, model in
            fake.listError = APIError.transport("offline")
            await model.load()
            XCTAssertEqual(model.projects.map(\.id), ["a"])
            XCTAssertNotNil(model.state.failure)
            XCTAssertTrue(model.presentation.showsStaleBanner)
        }
    }

    /// No matters in a status says so and offers the others.
    func testAnEmptyScopeSaysWhichStatusIsShown() async {
        await withList([matter("a", name: "A", status: "archived")]) { _, model in
            XCTAssertEqual(model.noMatches?.title, "No active matters")
            XCTAssertNil(model.noMatches?.clearTitle)
            model.showAllStatuses()
            XCTAssertNil(model.noMatches)
        }
    }

    /// A row says what the web's card says: the side with the client, the court with the
    /// reference, a far hearing in the accent, an overdue task in danger, and only the counts
    /// the server sent.
    func testTheRowReadsAsTheWebsCard() async {
        var p = matter("a", name: "Bhalla v. State", area: "writ", hearing: "2026-11-30",
                       client: "Ankit Bhalla", caseType: "CWP", number: "4412", year: "2025")
        p.ourSide = "petitioner"
        p.forumName = "Punjab and Haryana High Court"
        p.priority = "high"
        p.openTasks = 2
        p.nextTaskDueRaw = "2026-10-11"
        p.fileCount = 3
        p.chatCount = 1
        await withList([p]) { _, model in
            let card = model.card(p)
            XCTAssertEqual(card.area, "Writ / constitutional")
            XCTAssertEqual(card.client, "Ankit Bhalla (Petitioner)")
            XCTAssertEqual(card.court, "Punjab and Haryana High Court · CWP 4412/2025")
            XCTAssertEqual(card.hearing?.text, "30 Nov 2026")
            XCTAssertEqual(card.hearing?.tone, .accent)
            XCTAssertEqual(card.taskDue?.text, "11 Oct 2026 · overdue")
            XCTAssertEqual(card.taskDue?.tone, .danger)
            XCTAssertEqual(card.counts, "3 files · 1 chat · 2 open tasks")
            XCTAssertTrue(card.isHigh)
            XCTAssertTrue(card.spoken.hasPrefix("Bhalla v. State. Writ / constitutional."))
        }
        let thin = matter("b", name: "Thin")
        await withList([thin]) { _, model in
            let card = model.card(thin)
            XCTAssertNil(card.hearing)
            XCTAssertNil(card.taskDue)
            XCTAssertEqual(card.counts, "", "absent counts are not zero")
        }
    }

    /// An uploaded banner is fetched once per matter and version; a preset is never fetched.
    func testBannersAreFetchedOncePerVersion() async {
        var picture = matter("a", name: "A")
        picture.banner = "image"
        let preset = matter("b", name: "B")
        await withList([picture, preset]) { fake, model in
            fake.banner = Data([1, 2, 3])
            await model.loadBanner(for: picture)
            await model.loadBanner(for: picture)
            await model.loadBanner(for: preset)
            XCTAssertEqual(fake.bannerRequests.count, 1)
            XCTAssertEqual(fake.bannerRequests.first?.version, "2026-01-01T00:00:00.000Z")
            XCTAssertEqual(model.bannerImage(for: picture), Data([1, 2, 3]))
            XCTAssertNil(model.bannerImage(for: preset))
        }
    }
}

/// The docket under the matters: cases a matter holds are left out of its groups, search and
/// counts, but not out of `cases`.
final class CaseListHiddenCasesTests: XCTestCase {

    func testHiddenCasesLeaveTheGroupsButNotTheCases() async {
        await withHiddenDocket(all: false) { model in
            XCTAssertEqual(model.cases.count, 2)
            XCTAssertEqual(model.visible.map(\.id), ["k1"])
            XCTAssertEqual(model.groups.flatMap(\.cases).map(\.id), ["k1"])
            XCTAssertEqual(model.docketCases.map(\.id), ["k1"])
            XCTAssertEqual(model.count(for: .court(.highCourt)), 1)
            XCTAssertFalse(model.showsNoSearchResults)
        }
    }

    func testHidingEveryCaseIsNotANoMatchesState() async {
        await withHiddenDocket(all: true) { model in
            XCTAssertEqual(model.cases.count, 2)
            XCTAssertTrue(model.visible.isEmpty)
            XCTAssertFalse(model.showsNoSearchResults)
            XCTAssertNil(model.noMatches)
        }
    }
}

@MainActor
private func withHiddenDocket(all: Bool, _ body: @MainActor (CaseListViewModel) async -> Void) async {
    let fake = FakeCases()
    fake.cases = [
        docketCase("k1", title: "Kapoor v. Customs", court: "High Court of Delhi"),
        docketCase("k2", title: "Rao v. Union", court: "Madras High Court"),
    ]
    let model = CaseListViewModel(service: fake)
    await model.load()
    model.hiddenCaseIDs = all ? ["k1", "k2"] : ["k2"]
    await body(model)
}

private func docketCase(_ id: String, title: String, court: String) -> LegalCase {
    LegalCase(
        id: id, teamID: "team_1", cnr: nil, courtType: "hc", courtCode: "hc", caseNumber: nil,
        caseYear: nil, title: title, parties: nil, status: nil, stage: nil, nextHearingDateRaw: nil,
        filingDateRaw: nil, judge: nil, courtName: court, caseType: nil, diaryNumber: nil,
        category: nil, lastSyncedAtRaw: nil, createdAtRaw: nil, updatedAtRaw: nil, teamName: nil)
}
