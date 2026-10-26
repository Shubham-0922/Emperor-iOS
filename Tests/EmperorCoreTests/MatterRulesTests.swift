import XCTest
@testable import EmperorCore

/// The matter rules where the golden fixture cannot reach: paths only a typed Swift caller can
/// take, the ported `hearingTone` (a .jsx function, printed in the house date form), the Swift
/// conveniences around the port, and the edges of the JavaScript emulation.
final class MatterRulesTests: XCTestCase {

    private let today = "2026-10-12"

    // MARK: Money

    func testANumberAmountRoundsThroughToPrecisionAsTheServerDoes() throws {
        XCTAssertEqual(try MatterRules.rupeesToPaise(.number(1.005)), 101)
        XCTAssertEqual(try MatterRules.rupeesToPaise(.number(0.29)), 29)
        XCTAssertEqual(try MatterRules.rupeesToPaise(.number(1e11)), 10_000_000_000_000)
        XCTAssertThrowsError(try MatterRules.rupeesToPaise(.number(1e11 + 1), label: "Fee")) {
            XCTAssertEqual($0 as? MatterRuleError, MatterRuleError(message: "Fee is too large"))
        }
    }

    func testTheFieldsCeilingIsAboveTheServers() {
        // An amount the field accepts can still be refused by the server; forms check both.
        XCTAssertGreaterThan(INR.maxRupees, INR.serverMaxRupees)
        guard case .success(let parsed) = INR.parse("2,00,00,00,00,000") else { return XCTFail("parse refused") }
        XCTAssertGreaterThan(parsed.rupees, INR.serverMaxRupees)
        XCTAssertThrowsError(try MatterRules.rupeesToPaise(.number(parsed.rupees)))
    }

    func testIndianGroupingNeedsNoLocale() {
        XCTAssertEqual(JSCompat.indianGrouping("1"), "1")
        XCTAssertEqual(JSCompat.indianGrouping("1000"), "1,000")
        XCTAssertEqual(JSCompat.indianGrouping("100000"), "1,00,000")
        XCTAssertEqual(JSCompat.indianGrouping("10000000"), "1,00,00,000")
        XCTAssertEqual(INR.display(rupees: 125_000.5), "₹1,25,000.50")
        XCTAssertEqual(Ledger.rupees(0.5), "₹0.50")
        XCTAssertEqual(INR.words(paise: 12_500_050), "Rupees One Lakh Twenty Five Thousand and Fifty Paise Only")
        XCTAssertEqual(INR.words(paise: nil), "")
    }

    func testAnIntegerPaiseColumnWinsOverTheFloat() {
        let entry = Ledger.Entry(id: "e", kind: "fee", amountPaise: 2_500_050, amount: 1)
        XCTAssertEqual(Ledger.paise(of: entry), 2_500_050)
        XCTAssertEqual(Ledger.paise(of: Ledger.Entry(id: "e", kind: "fee", amount: 0.29)), 29)
        XCTAssertEqual(Ledger.paise(of: Ledger.Entry(id: "e", kind: "fee")), 0)
    }

    func testEveryPaymentModeHasAReferenceField() {
        for mode in MatterVocabulary.PaymentMode.allCases {
            XCTAssertNotNil(Ledger.referenceField(mode: mode.rawValue), mode.rawValue)
        }
        XCTAssertNil(Ledger.referenceField(mode: "bitcoin"))
    }

    // MARK: Dates

    func testHearingToneCountsIndianDaysAndUsesTheHouseDate() {
        XCTAssertEqual(MatterDates.hearingTone("2026-10-11", today: today),
                       MatterDates.HearingTone(text: "11 Oct 2026 · passed", tone: .mute, days: -1))
        XCTAssertEqual(MatterDates.hearingTone("2026-10-12", today: today),
                       MatterDates.HearingTone(text: "12 Oct 2026 · today", tone: .danger, days: 0))
        XCTAssertEqual(MatterDates.hearingTone("2026-10-13", today: today),
                       MatterDates.HearingTone(text: "13 Oct 2026 · tomorrow", tone: .warn, days: 1))
        XCTAssertEqual(MatterDates.hearingTone("2026-10-19", today: today),
                       MatterDates.HearingTone(text: "19 Oct 2026 · in 7d", tone: .warn, days: 7))
        XCTAssertEqual(MatterDates.hearingTone("2026-10-20", today: today),
                       MatterDates.HearingTone(text: "20 Oct 2026", tone: .mute, days: 8))
        // 20:00 UTC on the 12th is the 13th in India.
        XCTAssertEqual(MatterDates.hearingTone("2026-10-12T20:00:00Z", today: today)?.days, 1)
        // A zoneless SQLite timestamp is UTC.
        XCTAssertEqual(MatterDates.hearingTone("2026-10-12 19:00:00", today: today)?.days, 1)
        // September is "Sep", never en-IN's "Sept".
        XCTAssertEqual(MatterDates.hearingTone("2026-09-01", today: today)?.text, "01 Sep 2026 · passed")
        XCTAssertNil(MatterDates.hearingTone(nil, today: today))
        XCTAssertNil(MatterDates.hearingTone("soon", today: today))
    }

    func testTheIndianDayOfAnInstantIgnoresTheDevicesZone() {
        let at = Date(timeIntervalSince1970: 1_791_835_200)   // 2026-10-12T20:00:00Z
        XCTAssertEqual(MatterRules.istDay(at), "2026-10-13")
        XCTAssertEqual(MatterRules.istDay(at), WireDate.dayKey(at))
    }

    func testJavaScriptDateParsingCoversTheStoredShapes() {
        XCTAssertEqual(JSCompat.parseDate("2026-10-12"), 1_791_763_200_000)
        XCTAssertEqual(JSCompat.parseDate("2026-10-12 10:00:00"), 1_791_799_200_000)
        XCTAssertEqual(JSCompat.parseDate("2026-10-12T10:00:00+05:30"), 1_791_779_400_000)
        XCTAssertEqual(JSCompat.parseDate("2026-10-12T10:00:00.1234Z"), 1_791_799_200_123)
        XCTAssertEqual(JSCompat.parseDate("2026-02-30T10:00Z").map { JSCompat.isoString(epochMillis: $0) },
                       "2026-03-02T10:00:00.000Z")
        XCTAssertNil(JSCompat.parseDate("2026-10-12T25:00Z"))
        XCTAssertNil(JSCompat.parseDate("2026-13-01"))
        XCTAssertNil(JSCompat.parseDate("next Tuesday"))
        // A legacy shape V8 guesses at is deliberately not read.
        XCTAssertNil(JSCompat.parseDate("12/10/2026"))
    }

    func testGroupingWorksOnAnyTaskModel() {
        struct Row { let id: String; let key: MatterDates.TaskSortKey }
        let rows = [
            Row(id: "a", key: .init(status: "open", kind: "task", dueDate: "2026-10-13")),
            Row(id: "b", key: .init(status: "open", kind: "limitation", dueDate: "2026-10-18")),
            Row(id: "c", key: .init(status: "done", completedAt: "2026-10-10 09:00:00")),
            Row(id: "d", key: .init(status: "open")),
        ]
        let groups = MatterDates.group(rows, key: \.key, today: today)
        XCTAssertEqual(Set(groups.keys), Set(MatterDates.TaskGroup.allCases))
        XCTAssertEqual(groups[.week]?.map(\.id), ["b", "a"])
        XCTAssertEqual(groups[.done]?.map(\.id), ["c"])
        XCTAssertEqual(groups[.nodate]?.map(\.id), ["d"])
        XCTAssertEqual(groups[.overdue]?.count, 0)
    }

    // MARK: Rules

    func testRefreshWaitTakesDates() {
        let last = Date(timeIntervalSince1970: 1000)
        XCTAssertEqual(MatterRules.refreshWaitSeconds(lastAt: nil), 0)
        XCTAssertEqual(MatterRules.refreshWaitSeconds(lastAt: last, now: last.addingTimeInterval(60)), 240)
        XCTAssertEqual(MatterRules.refreshWaitSeconds(lastAt: last, now: last.addingTimeInterval(300)), 0)
    }

    func testFieldLimitsCoverTheForms() {
        XCTAssertEqual(MatterRules.fieldLimit("name"), 200)
        XCTAssertEqual(MatterRules.fieldLimit("ourSide"), 60)
        XCTAssertEqual(MatterRules.fieldLimit("ledger.reference"), 120)
        XCTAssertEqual(MatterRules.fieldLimit("person.phone"), 40)
        XCTAssertNil(MatterRules.fieldLimit("nonsense"))
    }

    func testBannerUploadsAreCheckedByTheirBytes() {
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] + [UInt8](repeating: 0, count: 8))
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0])
        let webp = Data(Array("RIFF".utf8) + [0, 0, 0, 0] + Array("WEBP".utf8) + [0])
        XCTAssertEqual(MatterRules.bannerImageType(png)?.ext, "png")
        XCTAssertEqual(MatterRules.bannerImageType(jpeg)?.mime, "image/jpeg")
        XCTAssertEqual(MatterRules.bannerImageType(webp)?.ext, "webp")
        XCTAssertNil(MatterRules.bannerImageType(Data("<svg/>".utf8)))
        XCTAssertNil(MatterRules.bannerImageType(Data()))
    }

    func testFreeTextSidesAndUnknownValuesAreShownAsWritten() {
        XCTAssertEqual(MatterVocabulary.OurSide.label(for: "petitioner"), "Petitioner")
        XCTAssertEqual(MatterVocabulary.OurSide.label(for: "Proforma respondent"), "Proforma respondent")
        XCTAssertEqual(MatterVocabulary.OurSide.label(for: nil), "")
        XCTAssertEqual(MatterMeta.sideLabel("other"), "Other")
        XCTAssertEqual(MatterRecord.sideLabelForTitle("other"), "")
        XCTAssertEqual(MatterVocabulary.Forum.tribunal.shortLabel, "Tribunal")
        XCTAssertEqual(MatterVocabulary.Forum.of("nonsense"), .other)
        XCTAssertEqual(MatterVocabulary.ProjectColor.label(of: "#ff0000"), "No colour")
        XCTAssertNil(MatterVocabulary.ProjectColor.normalize("Teal"))
    }

    func testAStoredExtIDIsComparedAndAMissingOneIsComputed() {
        let pick = MatterMeta.CasePick(courtCode: "DLHC", caseType: "W.P.(C)", caseNumber: "9", caseYear: "2020")
        let computed = MatterMeta.TrackedCaseCandidate(id: "c1", teamID: "t", courtName: "Elsewhere")
        XCTAssertNil(MatterMeta.findTrackedCase(pick, in: [computed], ownedTeamIDs: []))
        let sameFields = MatterMeta.TrackedCaseCandidate(id: "c2", teamID: "t", caseNumber: "9", caseYear: "2020",
                                                         caseType: "W.P.(C)", courtCode: "DLHC")
        XCTAssertEqual(sameFields.effectiveExtID, "DLHC|W.P.(C)|9|2020")
        XCTAssertEqual(MatterMeta.findTrackedCase(pick, in: [computed, sameFields], ownedTeamIDs: []), "c2")
    }

    func testActivityIgnoresAFutureEventDate() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let at = MatterMeta.activityAt(updated: "2026-09-01 10:00:00", created: nil, lastActivity: "2999-01-01", now: now)
        XCTAssertEqual(at, Date(timeIntervalSince1970: 1_788_256_800))
        XCTAssertNil(MatterMeta.activityAt(updated: nil, created: "junk", lastActivity: nil, now: now))
    }

    // MARK: Receipt

    func testAPDFReceiptDropsOnlyThePrintBar() {
        let entry = Ledger.Entry(id: "pl_1_ab12cd", kind: "payment", amountPaise: 2_500_000, entryDate: "2026-10-12", mode: "cash")
        let screen = MatterReceipt.html(entry: entry)
        let paper = MatterReceipt.html(entry: entry, includePrintBar: false)
        XCTAssertTrue(screen.contains("id=\"receipt-print\""))
        XCTAssertFalse(paper.contains("receipt-print"))
        XCTAssertEqual(screen.count - paper.count,
                       "<div class=\"bar\"><button type=\"button\" id=\"receipt-print\">Print</button><span>To keep a copy, choose “Save as PDF” in the print dialog.</span></div>\n".count)
        XCTAssertTrue(paper.contains(".bar { display: none; }"), "the stylesheet is unchanged")
        XCTAssertTrue(paper.contains("2026-27/AB12CD"))
    }

    func testTheAdvocatesMobileIsWrittenInternationally() {
        XCTAssertEqual(MatterReceipt.advocate(name: nil, title: nil, organization: nil, phone: "09876543210", email: nil).phone,
                       "+91 98765 43210")
        XCTAssertEqual(MatterReceipt.advocate(name: nil, title: nil, organization: nil, phone: "011-2345 6789", email: nil).phone,
                       "011-2345 6789")
    }

    // MARK: Chronology

    func testCourtDataArrivesInEitherWireShape() {
        XCTAssertEqual(MatterRecord.CourtItem.data(fromWire: .string("{\"courtNo\":\"5\"}"))["courtNo"], .string("5"))
        XCTAssertEqual(MatterRecord.CourtItem.data(fromWire: .object(["a": .number(1)]))["a"], .number(1))
        XCTAssertTrue(MatterRecord.CourtItem.data(fromWire: .string("not json")).isEmpty)
        XCTAssertTrue(MatterRecord.CourtItem.data(fromWire: nil).isEmpty)
    }

    func testEntryKeysAreUniqueAcrossTheMerge() {
        let entries = MatterRecord.chronology(
            updates: [MatterRecord.Update(id: "1", kind: "note", title: "Mine", eventDate: "2026-10-01")],
            court: [MatterRecord.CourtItem(id: "1", section: "orders", title: "O", itemDate: "2026-10-01")])
        XCTAssertEqual(entries.map(\.key), ["u:1", "c:1"])
        XCTAssertEqual(entries.map(\.title), ["Mine", "Order"])
        XCTAssertEqual(MatterRecord.sorted(entries).map(\.key), ["c:1", "u:1"])
    }
}
