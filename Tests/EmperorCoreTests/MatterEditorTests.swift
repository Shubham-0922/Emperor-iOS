import XCTest
@testable import EmperorCore

/// The matter forms: what each refuses before anything is sent (in the server's or the web form's
/// words), what each sends, and the order the details form sends things in. Driven on the main
/// actor through free functions — see `ChatViewModelTests`.
final class MatterEditorTests: XCTestCase {

    // MARK: - Ledger

    func testTheAmountIsReadAsTheWebReadsIt() async {
        await onMain {
            let editor = LedgerEditor(projectID: "p", kind: "payment", today: "2026-10-27", writes: FakeProjectWrites())
            editor.draft.amountText = ""
            XCTAssertEqual(editor.validate(), "Enter the amount.")
            editor.draft.amountText = "12abc"
            XCTAssertEqual(editor.validate(), "Use digits only, e.g. 25000 or 1,25,000.50.")
            editor.draft.amountText = "10.555"
            XCTAssertEqual(editor.validate(), "Paise take two decimals at most.")
            editor.draft.amountText = "0"
            XCTAssertEqual(editor.validate(), "The amount has to be more than ₹0.")
            editor.draft.amountText = "₹1,25,000.50/-"
            XCTAssertNil(editor.validate())
            XCTAssertEqual(editor.words, "Rupees One Lakh Twenty Five Thousand and Fifty Paise Only")
        }
    }

    /// The field takes up to ₹1e12, the server ₹1e11: refused here, not by a 400.
    func testAnAmountOverTheServersCeilingIsRefusedBeforeSending() async {
        await onMain {
            let writes = FakeProjectWrites()
            let editor = LedgerEditor(projectID: "p", kind: "fee", today: "2026-10-27", writes: writes)
            editor.draft.amountText = "100000000000"
            XCTAssertNil(editor.validate(), "₹1e11 itself is allowed")
            editor.draft.amountText = "100000000000.01"
            XCTAssertEqual(editor.validate(), "That amount is too large.")
            XCTAssertEqual(editor.words, "")
            let saved = await editor.save()
            XCTAssertNil(saved)
            XCTAssertEqual(editor.error, "That amount is too large.")
            XCTAssertTrue(writes.calls.isEmpty, "a refused amount was sent")
        }
    }

    func testOnlyAPaymentCarriesAModeAndOnlyAnExpenseACategory() async {
        await onMain {
            let writes = FakeProjectWrites()
            let editor = LedgerEditor(projectID: "p", kind: "payment", today: "2026-10-27", writes: writes)
            editor.draft.amountText = "25000"
            editor.draft.mode = "cheque"
            editor.draft.reference = " 004512, HDFC "
            XCTAssertEqual(editor.draft.referenceField?.label, "Cheque no. and bank")
            _ = await editor.save()
            let payment = writes.bodies["saveLedger"]?.last
            XCTAssertEqual(payment?["mode"], .string("cheque"))
            XCTAssertEqual(payment?["category"], .null)
            XCTAssertEqual(payment?["reference"], .string("004512, HDFC"))
            XCTAssertEqual(payment?["amount"], .number(25000))
            XCTAssertNil(payment?["id"])

            let expense = LedgerEditor(projectID: "p", kind: "expense", today: "2026-10-27", writes: writes)
            expense.draft.amountText = "500"
            XCTAssertEqual(expense.draft.referenceField?.label, Ledger.expenseReference.label)
            _ = await expense.save()
            XCTAssertEqual(writes.bodies["saveLedger"]?.last?["mode"], .null)
            XCTAssertEqual(writes.bodies["saveLedger"]?.last?["category"], .string("court_fee"))
        }
    }

    func testAnEditedEntryReadsItsAmountBackWithoutAFloatTail() async {
        await onMain {
            let entry = LedgerEntry(id: "pl-1", kind: "payment", amountPaise: 2_500_050, entryDateRaw: "2026-09-01", mode: nil)
            let editor = LedgerEditor(projectID: "p", entry: entry, today: "2026-10-27", writes: FakeProjectWrites())
            XCTAssertEqual(editor.draft.amountText, "25000.50")
            XCTAssertEqual(editor.draft.mode, "upi")
            XCTAssertEqual(editor.draft.entryDate, "2026-09-01")
            XCTAssertEqual(editor.title, "Edit payment")
        }
    }

    // MARK: - People

    func testAPersonsEmailAndPhoneAreCheckedAsTheWebChecksThem() async {
        await onMain {
            let editor = PersonEditor(projectID: "p", writes: FakeProjectWrites())
            XCTAssertEqual(editor.validate(), "Enter a name.")
            editor.draft.name = "Ankit"
            editor.draft.email = "ankit@example"
            XCTAssertEqual(editor.validate(), "That email address does not look complete.")
            editor.draft.email = "ankit@example.com"
            editor.draft.phone = "98-12"
            XCTAssertEqual(editor.validate(), "That phone number looks too short.")
            editor.draft.phone = "98765 43210 #9"
            XCTAssertEqual(editor.validate(), "phone may contain only digits, spaces and + ( ) - .")
            editor.draft.phone = "(011) 2338-1234 ext. 12"
            XCTAssertNil(editor.validate())
        }
    }

    // MARK: - Chronology

    func testAChronologyEntryNeedsATitleOrANote() async {
        await onMain {
            let writes = FakeProjectWrites()
            writes.nextHearing = "2026-11-02"
            let editor = ChronologyEditor(projectID: "p", today: "2026-10-27", writes: writes)
            XCTAssertEqual(editor.validate(), "A chronology entry needs a title or a note")
            editor.draft.body = "Notice issued."
            XCTAssertNil(editor.validate())
            editor.draft.precision = .year
            XCTAssertEqual(editor.draft.eventDate, "2026")
            let saved = await editor.save()
            XCTAssertEqual(saved?.nextHearingDate, "2026-11-02")
            XCTAssertEqual(writes.bodies["saveUpdate"]?.last?["eventDate"], .string("2026"))
        }
    }

    func testAnEditedEntryKeepsItsSourceAndPrecision() {
        let entry = MatterRecord.Entry(
            key: "u:pup-1", id: "pup-1", src: .ai, own: true, kind: "order", day: "2025-03", title: "Order",
            body: "", sourceRef: "Order.pdf", created: "", item: nil)
        let draft = ChronologyDraft(entry, today: "2026-10-27")
        XCTAssertEqual(draft.precision, .month)
        XCTAssertEqual(draft.eventDate, "2025-03")
        let body = draft.body(projectID: "p")
        XCTAssertEqual(body["source"], .string("ai"))
        XCTAssertEqual(body["sourceRef"], .string("Order.pdf"))
        XCTAssertEqual(body["id"], .string("pup-1"))
    }

    // MARK: - Tasks

    func testALimitationNeedsItsLastDate() async {
        await onMain {
            let editor = TaskEditor(projectID: "p", kind: "limitation", writes: FakeProjectWrites())
            XCTAssertEqual(editor.draft.priority, "high")
            XCTAssertEqual(editor.validate(), "Give the task a title.")
            editor.draft.title = "Appeal"
            XCTAssertEqual(editor.validate(), "A limitation entry needs its last date.")
            editor.draft.dueDate = "2026-02-30"
            XCTAssertEqual(editor.validate(), "That due date is not a real date.")
            editor.draft.dueDate = "2026-11-30"
            XCTAssertNil(editor.validate())
        }
    }

    func testTickingATaskSendsTheWholeTaskWithItsStatusFlipped() async {
        await onMain {
            let writes = FakeProjectWrites()
            let actions = MatterQuickActions(projectID: "prj-1", writes: writes)
            let task = ProjectTask(id: "pt-1", title: "File", notes: nil, dueDateRaw: "2026-10-10", kind: "filing",
                                   priority: "high", status: "open")
            let ok = await actions.toggle(task)
            XCTAssertTrue(ok)
            let body = writes.bodies["saveTask"]?.last
            XCTAssertEqual(body?["status"], .string("done"))
            XCTAssertEqual(body?["id"], .string("pt-1"))
            XCTAssertEqual(body?["dueDate"], .string("2026-10-10"))
            XCTAssertEqual(body?["notes"], .string(""))
        }
    }

    // MARK: - Delete

    func testDeleteMatchesTheTrimmedNameAndSendsTheStoredOne() async {
        await onMain {
            let writes = FakeProjectWrites()
            let deletion = MatterDeletion(project: Project(id: "prj-1", name: "Bhalla v. State"), writes: writes)
            XCTAssertFalse(deletion.matches("bhalla v. state"))
            XCTAssertFalse(deletion.matches("   "))
            XCTAssertTrue(deletion.matches("  Bhalla v. State "))
            deletion.typed = "Bhalla v. Stat"
            let refused = await deletion.delete()
            XCTAssertFalse(refused)
            XCTAssertTrue(writes.calls.isEmpty)
            deletion.typed = " Bhalla v. State "
            let done = await deletion.delete()
            XCTAssertTrue(done)
            XCTAssertEqual(writes.deleted.first?.confirm, "Bhalla v. State")
        }
    }

    // MARK: - Edit details: the banner's order

    func testAnEditWithANewImageUploadsItBeforeTheFields() async {
        await onMain {
            let writes = FakeProjectWrites()
            let editor = MatterDetailsEditor(project: Project(id: "prj-1", name: "M", banner: "teal"), writes: writes)
            editor.pickImage(pngBytes)
            XCTAssertEqual(editor.draft.banner, "image")
            let saved = await editor.save()
            XCTAssertNotNil(saved)
            XCTAssertEqual(writes.calls, ["upload", "save"])
            XCTAssertEqual(writes.saved.last?.json["banner"], .string("image"))
            XCTAssertEqual(writes.uploads.first?.mime, "image/png")
        }
    }

    func testAnEditThatDropsTheImageRemovesItFirstAndSendsThePreset() async {
        await onMain {
            let writes = FakeProjectWrites()
            let editor = MatterDetailsEditor(
                project: Project(id: "prj-1", name: "M", color: "green", banner: "image"), writes: writes)
            XCTAssertEqual(editor.draft.banner, "image")
            editor.pickPreset(.wine)
            _ = await editor.save()
            XCTAssertEqual(writes.calls, ["removeBanner", "save"])
            XCTAssertEqual(writes.saved.last?.json["banner"], .string("wine"))
        }
    }

    func testAFailedUploadOnAnEditSavesNothing() async {
        await onMain {
            let writes = FakeProjectWrites()
            writes.uploadError = APIError.server(status: 400, message: "The banner file is not the image type it claims to be")
            let editor = MatterDetailsEditor(project: Project(id: "prj-1", name: "M"), writes: writes)
            editor.pickImage(pngBytes)
            let saved = await editor.save()
            XCTAssertNil(saved)
            XCTAssertEqual(writes.calls, ["upload"])
            XCTAssertEqual(editor.error, "The banner image was not uploaded: The banner file is not the image type it claims to be.")
        }
    }

    func testANewMattersImageGoesAfterTheFieldsAndFallsBackToThePreset() async {
        await onMain {
            let writes = FakeProjectWrites()
            writes.uploadError = APIError.server(status: 400, message: "too big")
            let editor = MatterDetailsEditor(project: nil, writes: writes, defaultBanner: .forest)
            editor.draft.name = "New one"
            editor.pickImage(pngBytes)
            let saved = await editor.save()
            XCTAssertEqual(saved?.id, "prj-new-1")
            XCTAssertEqual(writes.calls, ["save", "upload", "patch"])
            XCTAssertEqual(writes.patched.last?.fields, .banner("forest"))
            XCTAssertEqual(editor.savedMessage, "Saved, but the banner image was not uploaded (too big).")
        }
    }

    func testTheDetailsFormRefusesWhatTheServerWould() async {
        await onMain {
            let editor = MatterDetailsEditor(project: Project(id: "prj-1", name: "M"), writes: FakeProjectWrites())
            editor.draft.name = "  "
            XCTAssertEqual(editor.validate(), "Give the matter a name.")
            editor.draft.name = "M"
            editor.draft.caseYear = "12345678901"
            XCTAssertEqual(editor.validate(), "caseYear is longer than 10 characters")
            editor.draft.caseYear = "2025"
            editor.draft.nextHearingDate = "2026-13-01"
            XCTAssertNotNil(editor.validate())
            editor.pickImage(Data("GIF89a".utf8))
            XCTAssertEqual(editor.error, "The banner must be a PNG, JPEG or WebP image")
            XCTAssertNotEqual(editor.draft.banner, "image")
        }
    }

    // MARK: - New matter

    func testANotFiledMatterIsCreatedWithItsCourtStatus() async {
        await onMain {
            let writes = FakeProjectWrites()
            let model = NewMatterViewModel(
                writes: writes, tracking: nil,
                existing: [Project(id: "a", banner: "navy"), Project(id: "b", banner: "slate")])
            XCTAssertEqual(model.banner, .indigo, "the least-used preset")
            XCTAssertEqual(model.validate(), "Search the court records and choose the case — or pick “Not filed yet” or “Add later”.")
            model.court = .notFiled
            XCTAssertEqual(model.validate(), "Give the matter a name.")
            model.name = " Bhalla v. State "
            let made = await model.create()
            XCTAssertEqual(made?.projectID, "prj-new-1")
            XCTAssertEqual(made?.existed, false)
            let body = writes.saved.last?.json
            XCTAssertEqual(body?["name"], .string("Bhalla v. State"))
            XCTAssertEqual(body?["courtStatus"], .string("not_filed"))
            XCTAssertEqual(body?["banner"], .string("indigo"))
        }
    }

    func testAddLaterSendsNoCourtStatus() async {
        await onMain {
            let writes = FakeProjectWrites()
            let model = NewMatterViewModel(writes: writes, tracking: nil)
            model.court = .later
            model.name = "M"
            _ = await model.create()
            XCTAssertNil(writes.saved.last?.json["courtStatus"])
        }
    }

    func testAFoundCaseIsTrackedThenTheMatterMadeFromIt() async {
        await onMain {
            let writes = FakeProjectWrites()
            writes.existed = true
            let search = FakeTrackingSearch()
            search.outcome = .saved(id: "case-9")
            let model = NewMatterViewModel(
                writes: writes, tracking: CaseTracking(cases: FakeCases(), search: search))
            model.choose(CourtSearchResult(caseNumber: "12", caseYear: "2025", cnr: "DLHC01", title: "ANKIT BHALLA VS STATE"))
            XCTAssertEqual(model.titleFromCase, "Ankit Bhalla v. State")
            XCTAssertNil(model.validate(), "a found case names the matter")
            let made = await model.create()
            XCTAssertEqual(made?.projectID, "prj-from-case-9")
            XCTAssertEqual(made?.existed, true)
            XCTAssertEqual(writes.fromCase.first?.name, nil, "left blank, the server names it")
            XCTAssertEqual(NewMatterViewModel.createdMessage(existed: true),
                           "You already have a matter for this case — opening it.")
        }
    }

    // MARK: - Court

    func testRefreshingTooSoonHoldsTheButtonForTheServersWait() async {
        await onMain {
            let writes = FakeProjectWrites()
            let start = Date(timeIntervalSince1970: 1_000_000)
            let court = MatterCourtActions(projectID: "p", writes: writes, tracking: nil, now: { start })
            let first = await court.refresh()
            XCTAssertTrue(first)
            XCTAssertEqual(court.message, "Court record refreshed — 3 hearings, 1 order")

            writes.refreshOutcome = .tooSoon(retryAfter: 240, message: "try again in 4 min")
            let second = await court.refresh()
            XCTAssertFalse(second)
            XCTAssertEqual(court.waitSeconds(), 240)
            XCTAssertEqual(court.refreshLabel(), "Refresh in 4:00")
            XCTAssertEqual(court.waitSeconds(at: start.addingTimeInterval(200)), 40)
            let third = await court.refresh()
            XCTAssertFalse(third)
            XCTAssertEqual(writes.calls, ["refresh", "refresh"], "the court was asked inside its wait")
        }
    }

    func testLinkingAFoundCaseEndsNotFiledYet() async {
        await onMain {
            let writes = FakeProjectWrites()
            let cases = FakeCases()
            var tracked = LegalCase(id: "case-x")
            tracked.cnr = "DLHC01"
            cases.cases = [tracked]
            let court = MatterCourtActions(
                projectID: "prj-1", writes: writes, tracking: CaseTracking(cases: cases, search: FakeTrackingSearch()))
            let ok = await court.link(CourtSearchResult(cnr: "DLHC01"), matter: Project(id: "prj-1", courtStatus: "not_filed"))
            XCTAssertTrue(ok)
            XCTAssertEqual(writes.links, ["case-x"])
            XCTAssertEqual(writes.calls, ["link", "patch"])
            XCTAssertEqual(writes.patched.last?.fields, .courtStatus(nil))
        }
    }
}

private let pngBytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00])

@MainActor
private func onMain(_ body: @MainActor () async -> Void) async {
    await body()
}
