import XCTest
@testable import EmperorCore

/// Noon in India on 12 Oct 2026 — every "today" in these tests.
private let noonIST: Date = ISO8601DateFormatter().date(from: "2026-10-12T06:30:00Z")!

private func workspaceDetail(
    project: Project = Project(
        id: "p1", name: "Bhalla v. State", client: "Ankit Bhalla", forumName: "Punjab and Haryana High Court",
        caseNumber: "4412", caseYear: "2025", caseType: "CWP", cnr: "PHHC010044122025",
        nextHearingDateRaw: "2026-10-14", linkedCaseID: "case-x", practiceArea: "writ",
        ourSide: "petitioner", oppositeParty: "State of Haryana"),
    linked: Bool = true
) -> ProjectDetail {
    ProjectDetail(
        project: project,
        updates: [
            ProjectUpdate(id: "u1", kind: "note", title: "Brief received", eventDateRaw: "2026-09-01", source: "manual"),
            ProjectUpdate(id: "u2", kind: "order", title: "Notice issued", eventDateRaw: "2026-09-20", source: "ai"),
        ],
        chats: [ProjectChat(id: "c1", title: "Draft")],
        courtHistory: linked ? [
            CourtHistoryItem(id: "h1", section: "hearings", title: "Arguments", itemDateRaw: "2026-10-14",
                             data: ["courtNo": .string("12"), "itemNo": .string("7")]),
            CourtHistoryItem(id: "h0", section: "hearings", title: "Admission", itemDateRaw: "2026-09-20"),
            CourtHistoryItem(id: "o1", section: "orders", title: "Order", itemDateRaw: "2026-09-20",
                             data: ["type": .string("Order"), "summary": .string("Notice issued.")]),
            CourtHistoryItem(id: "a1", section: "applications", title: "IA 1/2026", itemDateRaw: "2026-09-01",
                             status: "Pending"),
            CourtHistoryItem(id: "p1", section: "parties", title: "Ankit Bhalla", subtitle: "Petitioner"),
            CourtHistoryItem(id: "p2", section: "parties", title: "State of Haryana", subtitle: "Respondent"),
            CourtHistoryItem(id: "p3", section: "parties", title: "Adv. R. Mehta", subtitle: "Our advocate"),
        ] : [],
        linkedCase: linked ? LinkedCase(
            id: "case-x", title: "ANKIT BHALLA VS STATE", courtName: "Punjab and Haryana High Court",
            caseType: "CWP", caseNumber: "4412", caseYear: "2025", nextHearingDateRaw: "2026-10-14",
            stage: "Admission", status: "Pending", lastSyncedAtRaw: "2026-10-01T04:00:00.000Z") : nil,
        tasks: [
            ProjectTask(id: "late", title: "File rejoinder", dueDateRaw: "2026-10-10", kind: "filing", status: "open"),
            ProjectTask(id: "lim", title: "Appeal", dueDateRaw: "2026-10-15", kind: "limitation", status: "open"),
            ProjectTask(id: "later", title: "Inspect", dueDateRaw: "2026-12-01", kind: "task", status: "open"),
            ProjectTask(id: "nodate", title: "Call client", kind: "task", status: "open"),
            ProjectTask(id: "done", title: "Vakalatnama", dueDateRaw: "2026-09-01", status: "done",
                        completedAtRaw: "2026-09-02T05:00:00.000Z"),
        ],
        ledger: [
            LedgerEntry(id: "f1", kind: "fee", title: "Drafting", amountPaise: 1_000_000, entryDateRaw: "2026-09-01"),
            LedgerEntry(id: "pay", kind: "payment", amountPaise: 1_500_000, entryDateRaw: "2026-09-05",
                        mode: "upi", reference: "UTR123"),
            LedgerEntry(id: "e1", kind: "expense", title: "Court fee", amountPaise: 50_000,
                        entryDateRaw: "2026-09-02", category: "court_fee"),
            LedgerEntry(id: "e2", kind: "expense", amountPaise: 20_000, entryDateRaw: "2026-09-03", category: "travel"),
        ],
        people: [
            ProjectPerson(id: "x", role: "opposite_party", name: "State of Haryana", createdAtRaw: "2026-09-01 10:00:00"),
            ProjectPerson(id: "c2", role: "client", name: "Second", createdAtRaw: "2026-09-02 10:00:00"),
            ProjectPerson(id: "c1", role: "client", name: "Ankit Bhalla", phone: "98765 43210", createdAtRaw: "2026-09-01 10:00:00"),
            ProjectPerson(id: "w", role: "bailiff", name: "Odd role"),
        ])
}

@MainActor
private func withWorkspace(
    _ detail: ProjectDetail? = workspaceDetail(), section: String? = nil, fileCount: Int? = nil,
    _ body: @MainActor (FakeProjects, MatterWorkspaceViewModel) async -> Void
) async {
    let fake = FakeProjects()
    fake.detail = detail
    let model = MatterWorkspaceViewModel(
        projectID: "p1", service: fake, section: section, fileCount: fileCount, now: { noonIST })
    await model.load()
    await body(fake, model)
}

final class MatterWorkspaceViewModelTests: XCTestCase {

    /// The server's 404 means the matter is gone or not this user's.
    func testA404IsAMissingMatter() async {
        await withWorkspace(nil) { _, model in
            XCTAssertEqual(model.state, .missing)
            XCTAssertNil(model.detail)
        }
    }

    /// A failed refresh keeps the record on screen and says so; a first load that fails shows
    /// the failure.
    func testA500KeepsTheRecordAndSaysSo() async {
        await withWorkspace { fake, model in
            fake.detailError = APIError.server(status: 500, message: "Database is locked")
            await model.reload()
            XCTAssertEqual(model.state, .loaded)
            XCTAssertNotNil(model.detail)
            XCTAssertEqual(model.toast, "Database is locked")
        }
        let fake = FakeProjects()
        fake.detailError = APIError.server(status: 500, message: "Database is locked")
        await failedFirstLoad(fake)
    }

    /// A 404 on a refresh means the matter has gone since.
    func testA404OnRefreshIsMissingToo() async {
        await withWorkspace { fake, model in
            fake.detail = nil
            await model.reload()
            XCTAssertEqual(model.state, .missing)
        }
    }

    /// Ask, Files and Drafts stay off the bar while their routes are not built.
    func testContentSectionsAreHiddenWhileUnavailable() async {
        XCTAssertFalse(MatterAvailability.contentSections)
        await withWorkspace(section: "files") { _, model in
            XCTAssertEqual(model.visibleSections, [.overview, .chronology, .court, .tasks, .fees, .people])
            XCTAssertEqual(model.section, .overview, "an unavailable section opens the overview")
        }
        await withWorkspace(section: "court") { _, model in
            XCTAssertEqual(model.section, .court)
        }
    }

    /// The bar's numbers: waiting things only; Tasks in danger with an overdue task.
    func testNavCounts() async {
        await withWorkspace { _, model in
            let counts = model.navCounts
            XCTAssertEqual(counts[.tasks], .init(count: 4, danger: true))
            XCTAssertEqual(counts[.court], .init(dot: true))
            XCTAssertEqual(counts[.people], .init(count: 4))
            XCTAssertEqual(counts[.ask], .init(count: 1))
            // Two updates, two hearings and one order.
            XCTAssertEqual(counts[.chronology]?.count, 5)
            XCTAssertNil(counts[.fees])
        }
        var calm = workspaceDetail(linked: false)
        calm.tasks = [ProjectTask(id: "t", dueDateRaw: "2026-10-20", status: "open")]
        calm.people = []
        await withWorkspace(calm) { _, model in
            XCTAssertEqual(model.navCounts[.tasks], .init(count: 1, danger: false))
            XCTAssertNil(model.navCounts[.court])
            XCTAssertNil(model.navCounts[.people])
        }
    }

    /// The header reads the matter, falling back to the linked case.
    func testTheHeader() async {
        await withWorkspace { _, model in
            let h = try? XCTUnwrap(model.header)
            XCTAssertEqual(h?.name, "Bhalla v. State")
            XCTAssertEqual(h?.forumLine, "Punjab and Haryana High Court · CWP 4412/2025")
            XCTAssertEqual(h?.cnrLabel, "CNR")
            XCTAssertEqual(h?.parties, "Ankit Bhalla (Petitioner) v. State of Haryana")
            XCTAssertEqual(h?.nextText, "Next hearing 14 Oct 2026 · in 2 days")
            XCTAssertEqual(h?.nextTone, .warn)
            XCTAssertEqual(h?.notFiled, false)
        }
        let bare = ProjectDetail(project: Project(id: "p1", name: "Advice", courtStatus: "not_filed"))
        await withWorkspace(bare) { _, model in
            XCTAssertEqual(model.header?.nextText, "No hearing date")
            XCTAssertEqual(model.header?.notFiled, true)
            XCTAssertEqual(model.standing?.headline, "Not filed in court yet.")
            XCTAssertEqual(model.latestOrderEmpty, "Not filed yet")
        }
    }

    func testTheHearingChipTones() {
        func tone(_ days: Int) -> MatterWorkspaceViewModel.HearingChipTone {
            MatterWorkspaceViewModel.hearingChip(
                MatterRecord.NextHearing(day: "2026-10-12", from: .project, days: days, listing: nil, latest: nil)).1
        }
        XCTAssertEqual(tone(-1), .mute)
        XCTAssertEqual(tone(0), .danger)
        XCTAssertEqual(tone(1), .danger)
        XCTAssertEqual(tone(5), .warn)
        XCTAssertEqual(tone(30), .accent)
    }

    /// The setup checklist: four of six known done without the files count; the documents
    /// step is unknowable until it is given.
    func testSetupPercent() async {
        await withWorkspace { _, model in
            let steps = model.setupSteps
            XCTAssertEqual(steps.map(\.key), ["court", "side", "parties", "practice", "documents", "contact"])
            XCTAssertNil(steps[4].done)
            XCTAssertEqual(steps[5].done, true)
            XCTAssertEqual(model.setupPercent, 83)
        }
        await withWorkspace(fileCount: 3) { _, model in
            XCTAssertEqual(model.setupPercent, 100)
        }
        let bare = ProjectDetail(project: Project(id: "p1"))
        await withWorkspace(bare, fileCount: 0) { _, model in
            XCTAssertEqual(model.setupPercent, 0)
        }
    }

    /// Where things stand, the to-do tile, the fees tile and the latest order.
    func testTheOverview() async {
        await withWorkspace { _, model in
            XCTAssertEqual(model.standing?.headline, "Next in court in 2 days.")
            XCTAssertEqual(model.standing?.detail,
                           "Wednesday, 14 Oct 2026 · Court 12 · Item 7 · Punjab and Haryana High Court")
            let todo = model.todo
            XCTAssertEqual(todo.open, 4)
            XCTAssertEqual(todo.overdue, 1)
            XCTAssertEqual(todo.rows.map(\.dueText), ["2d late", "In 3 days", "01 Dec 2026"])
            let fees = model.feesSummary
            XCTAssertEqual(fees.paid, 15000)
            XCTAssertEqual(fees.stillDue, 0)
            XCTAssertEqual(fees.percent, 100)
            XCTAssertEqual(model.latestOrder?.title, "Order")
            XCTAssertEqual(model.latestOrder?.fromCourt, true)
            XCTAssertEqual(model.latestOrder?.when, "20 Sep 2026 · 22 days ago")
            // Nothing in the future, nothing that is a task; newest first.
            XCTAssertEqual(model.timeline.first?.day, "2026-09-20")
            XCTAssertFalse(model.timeline.contains { $0.day > "2026-10-12" })
        }
        await withWorkspace(workspaceDetail(linked: false)) { _, model in
            // An order entered by hand stands in for the court's.
            XCTAssertEqual(model.latestOrder?.title, "Notice issued")
            XCTAssertEqual(model.latestOrder?.fromCourt, false)
        }
    }

    /// The chronology merges the matter's record and the court's, in either order.
    func testTheChronologyOrders() async {
        await withWorkspace { _, model in
            let newest = model.chronology(newestFirst: true)
            let oldest = model.chronology(newestFirst: false)
            XCTAssertEqual(newest.count, 5)
            XCTAssertEqual(newest.first?.day, "2026-10-14")
            XCTAssertEqual(oldest.first?.day, "2026-09-01")
            XCTAssertEqual(newest.map { MatterWorkspaceViewModel.sourceLabel($0) }.filter { $0 == "AI" }.count, 1)
        }
    }

    /// Tasks in the web's groups; a critical kind is marked; a done task says when.
    func testTaskGroups() async {
        await withWorkspace { _, model in
            let groups = model.taskGroups
            XCTAssertEqual(groups.map(\.group), [.overdue, .week, .later, .nodate, .done])
            XCTAssertEqual(groups[1].rows.first?.critical, true)
            XCTAssertEqual(groups[1].rows.first?.kindLabel, "Limitation")
            XCTAssertEqual(groups[0].rows.first?.due?.rel, "2d overdue")
            XCTAssertEqual(groups[4].rows.first?.doneText, "Done 02 Sep 2026")
        }
    }

    /// Fees: an advance shows as held, not as a negative debt; columns per kind; categories
    /// narrow the expenses.
    func testFees() async {
        await withWorkspace { _, model in
            let tiles = model.feeTiles
            XCTAssertEqual(tiles.map(\.label), ["Billed", "Received", "Advance held", "Expenses"])
            XCTAssertEqual(tiles[2].value, Ledger.rupees(5000))
            XCTAssertEqual(tiles[2].tone, .accent)
            XCTAssertEqual(tiles[1].tone, .success)
            XCTAssertEqual(tiles[0].detail, "1 fee entry")
            let columns = model.feeColumns
            XCTAssertEqual(columns.map(\.kind), ["fee", "payment", "expense"])
            XCTAssertEqual(columns[1].entries.first?.badge, "UPI")
            XCTAssertEqual(columns[1].entries.first?.reference, "UTR123")
            XCTAssertEqual(columns[2].entries.map(\.title), ["Travel", "Court fee"])
            XCTAssertEqual(model.feeCategories.map(\.key), ["court_fee", "travel"])
            model.feeCategory = "travel"
            XCTAssertEqual(model.feeColumns[2].entries.map(\.id), ["e2"])
            XCTAssertEqual(model.feeColumns[2].count, 2)
            model.feeCategory = "notary"
            XCTAssertNil(model.activeFeeCategory)
            XCTAssertEqual(model.feeColumns[2].entries.count, 2)
        }
    }

    /// People by role, in the vocabulary's order, oldest first; an unknown role is Other.
    func testPeopleByRole() async {
        await withWorkspace { _, model in
            let groups = model.peopleByRole
            XCTAssertEqual(groups.map(\.role), [.client, .oppositeParty, .other])
            XCTAssertEqual(groups[0].people.map(\.id), ["c1", "c2"])
        }
        XCTAssertEqual(MatterWorkspaceViewModel.telLink("98765 43210"), "tel:+919876543210")
        XCTAssertEqual(MatterWorkspaceViewModel.telLink("011-2338 1234"), "tel:01123381234")
        XCTAssertEqual(MatterWorkspaceViewModel.telLink("+44 20 7946 0958"), "tel:+442079460958")
        XCTAssertNil(MatterWorkspaceViewModel.telLink("  "))
        XCTAssertEqual(MatterWorkspaceViewModel.phoneShown("9876543210"), "+91 98765 43210")
        XCTAssertEqual(MatterWorkspaceViewModel.mailLink("a@b.in"), "mailto:a@b.in")
        XCTAssertNil(MatterWorkspaceViewModel.mailLink("not an address"))
    }

    /// The court record: hearings newest first with the one ahead marked, orders, applications
    /// with their status tone, and the parties by side.
    func testCourtGroups() async {
        await withWorkspace { _, model in
            let groups = model.courtGroups
            XCTAssertEqual(groups.map(\.key), ["hearings", "orders", "applications"])
            XCTAssertEqual(groups[0].rows.map(\.id), ["h1", "h0"])
            XCTAssertEqual(groups[0].rows.first?.rel, "in 2 days")
            XCTAssertNil(groups[0].rows.last?.rel)
            XCTAssertEqual(groups[1].rows.first?.lines, ["Notice issued."])
            XCTAssertEqual(groups[2].rows.first?.badgeTone, .warning)
            let parties = model.courtParties
            XCTAssertEqual(parties?.first, ["Ankit Bhalla"])
            XCTAssertEqual(parties?.firstCounsel, ["Adv. R. Mehta"])
            XCTAssertEqual(parties?.second, ["State of Haryana"])
            XCTAssertNil(model.courtNotice)
            XCTAssertEqual(model.linkedFacts.map(\.label), ["Stage", "Status", "Next date", "Last synced"])
            XCTAssertEqual(model.linkedFacts.last?.value, "01 Oct 2026, 09:30")
        }
        // A link the user can no longer see is said, not hidden.
        await withWorkspace(workspaceDetail(linked: false)) { _, model in
            XCTAssertEqual(model.courtGroups, [])
            XCTAssertTrue(model.courtNotice?.hasPrefix("The court case linked to this matter is no longer available") == true)
        }
    }

    /// The banner is fetched only for an uploaded picture, once per version.
    func testTheBannerLoadsOnce() async {
        var detail = workspaceDetail()
        detail.project.banner = "image"
        detail.project.updatedAtRaw = "v1"
        await withWorkspace(detail) { fake, model in
            fake.banner = Data([9])
            await model.loadBanner()
            await model.loadBanner()
            XCTAssertEqual(fake.bannerRequests.count, 1)
            XCTAssertEqual(model.bannerData, Data([9]))
        }
    }
}

@MainActor
private func failedFirstLoad(_ fake: FakeProjects) async {
    let model = MatterWorkspaceViewModel(projectID: "p1", service: fake, now: { noonIST })
    await model.load()
    guard case .failed(let failure) = model.state else {
        return XCTFail("expected a failure, got \(model.state)")
    }
    XCTAssertEqual(failure.message, "Database is locked")
    XCTAssertNil(model.toast)
}
