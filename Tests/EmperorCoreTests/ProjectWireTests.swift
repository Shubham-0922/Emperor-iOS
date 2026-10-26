import XCTest
@testable import EmperorCore

/// `GET /project` as the server sends it: the matter, its record, chats, the linked case and its
/// court record, tasks, ledger, people and totals.
///
/// The first test is the regression for matters that would not open: `courtHistory[].data` is a
/// parsed JSON **object** on the wire, and the earlier model read it as text, so any matter
/// linked to a case with scraped data failed to decode as a whole.
final class ProjectWireTests: XCTestCase {

    private func decode(_ json: String) throws -> ProjectDetail {
        let response = try JSONDecoder().decode(ProjectDetailResponse.self, from: Data(json.utf8))
        let project = try XCTUnwrap(response.project)
        return ProjectDetail(response: response, project: project)
    }

    static let full = """
        {"success":true,
         "project":{"id":"prj-writ","user_id":"42","name":"Bhalla v. State of Haryana","client":"Ankit Bhalla",
           "description":"Challenge to the tender cancellation.","forum_type":"high_court",
           "forum_name":"Punjab and Haryana High Court","case_number":"4412","case_year":"2025",
           "cnr":"PHHC010044122025","stage":"Admission","status":"active","priority":"high",
           "next_hearing_date":"2026-10-14","filing_date":"2025-03-01","linked_case_id":"case-x",
           "created_at":"2025-03-01T10:00:00.000Z","updated_at":"2026-10-01T10:00:00.000Z",
           "archived_at":null,"case_type":"CWP","color":"teal","banner":"teal","practice_area":"writ",
           "our_side":"petitioner","court_status":null,"opposite_party":"State of Haryana"},
         "updates":[
           {"id":"u1","project_id":"prj-writ","user_id":"42","kind":"note","title":"Brief received",
            "body":"From the client.","event_date":"2026-09-01","status":null,
            "payload":{"pages":3},"created_at":"2026-09-01 10:00:00","source":"manual","source_ref":null},
           {"id":"u2","project_id":"prj-writ","user_id":"42","kind":"order","title":"Notice issued",
            "body":null,"event_date":"2026-09-20","status":null,"payload":null,
            "created_at":"2026-09-21 09:00:00","source":"ai","source_ref":"Order 20.09.2026.pdf"}],
         "chats":[{"id":"c1","title":"Draft the rejoinder","updated_at":"2026-10-01 08:00:00","linked_at":null}],
         "courtHistory":[
           {"id":"i1","section":"hearings","title":"Arguments","subtitle":null,"item_date":"2026-10-14",
            "status":null,"source":"ecourts",
            "data":{"courtNo":"12","itemNo":7,"coram":"Hon'ble Mr. Justice A","listType":"Supplementary",
                    "nested":{"a":[1,2,{"b":null}]},"flag":true}},
           {"id":"i2","section":"orders","title":"Order","subtitle":null,"item_date":"2026-09-20",
            "status":null,"source":"ecourts","data":{"type":"Order","summary":"Notice issued."}},
           {"id":"i3","section":"parties","title":"Ankit Bhalla","subtitle":"Petitioner","item_date":null,
            "status":null,"source":"ecourts","data":null}],
         "linkedCase":{"id":"case-x","title":"ANKIT BHALLA VS STATE OF HARYANA","court_name":"Punjab and Haryana High Court",
           "court_type":"hc","case_type":"CWP","case_number":"4412","case_year":"2025","cnr":"PHHC010044122025",
           "next_hearing_date":"2026-10-14","stage":"Admission","status":"Pending","last_synced_at":"2026-10-01T04:00:00.000Z"},
         "tasks":[{"id":"t1","project_id":"prj-writ","user_id":"42","title":"File rejoinder","notes":null,
           "due_date":"2026-10-10","kind":"filing","priority":"high","status":"open","completed_at":null,
           "created_at":"2026-09-01 10:00:00","updated_at":"2026-09-01 10:00:00"}],
         "ledger":[{"id":"l1","project_id":"prj-writ","user_id":"42","kind":"fee","title":"Drafting",
           "amount_paise":5000000,"amount":50000,"entry_date":"2026-09-01","mode":null,"reference":null,
           "category":null,"receipt_file":null,"notes":null,"created_at":"2026-09-01 10:00:00"}],
         "people":[{"id":"pp1","project_id":"prj-writ","user_id":"42","role":"client","name":"Ankit Bhalla",
           "phone":"9876543210","email":"ankit@example.com","address":null,"notes":null,
           "created_at":"2026-09-01 10:00:00"}],
         "totals":{"billed":50000,"received":0,"outstanding":50000,"expenses":0}}
        """

    /// The regression: a linked matter with scraped `data` objects decodes, whole, and the data
    /// is there to read.
    func testALinkedMatterWithScrapedDataObjectsDecodes() throws {
        let detail = try decode(Self.full)

        XCTAssertEqual(detail.project.id, "prj-writ")
        XCTAssertEqual(detail.courtHistory.count, 3)
        let hearing = try XCTUnwrap(detail.courtHistory.first { $0.id == "i1" })
        XCTAssertEqual(hearing.data["courtNo"], .string("12"))
        XCTAssertEqual(hearing.text("itemNo"), "7")
        XCTAssertEqual(hearing.data["flag"], .bool(true))
        XCTAssertEqual(hearing.source, "ecourts")
        XCTAssertEqual(detail.courtHistory.first { $0.id == "i3" }?.data, [:])
        XCTAssertEqual(MatterRecord.hearingFacts(hearing.recordItem).where, "Court 12 · Item 7")

        XCTAssertEqual(detail.updates.map(\.id), ["u1", "u2"])
        XCTAssertEqual(detail.updates[0].payloadRaw, #"{"pages":3}"#)
        XCTAssertEqual(detail.updates[1].source, "ai")
        XCTAssertEqual(detail.updates[1].sourceRef, "Order 20.09.2026.pdf")
        XCTAssertEqual(detail.chats.first?.title, "Draft the rejoinder")
        XCTAssertEqual(detail.linkedCase?.courtName, "Punjab and Haryana High Court")
        XCTAssertEqual(detail.linkedCase?.lastSyncedAtRaw, "2026-10-01T04:00:00.000Z")
        XCTAssertEqual(detail.tasks.first?.kind, "filing")
        XCTAssertEqual(detail.ledger.first?.amountPaise, 5_000_000)
        XCTAssertEqual(detail.people.first?.phone, "9876543210")
        XCTAssertEqual(detail.totals.outstanding, 50000)
        XCTAssertEqual(detail.project.ourSide, "petitioner")
    }

    /// An older server sent `data` as the column's JSON text; it reads the same.
    func testDataSentAsJSONTextReadsAsTheObject() throws {
        let detail = try decode("""
            {"success":true,"project":{"id":"p"},
             "courtHistory":[{"id":"i1","section":"hearings","item_date":"2026-10-14",
               "data":"{\\"courtNo\\":\\"4\\",\\"itemNo\\":\\"21\\"}"},
               {"id":"i2","section":"orders","title":"Order","data":"not json"},
               {"id":"i3","section":"orders","title":"Order","data":[1,2]}]}
            """)
        XCTAssertEqual(detail.courtHistory.first?.data["courtNo"], .string("4"))
        XCTAssertEqual(detail.courtHistory.first?.text("itemNo"), "21")
        XCTAssertEqual(detail.courtHistory[1].data, [:])
        XCTAssertEqual(detail.courtHistory[2].data, [:])
    }

    /// A server that predates part of the payload sends fewer keys; every list is then empty
    /// and the totals are summed from the ledger.
    func testAbsentListsAreEmptyAndTotalsComeFromTheLedger() throws {
        let detail = try decode("""
            {"success":true,"project":{"id":"p","name":"M"},
             "ledger":[{"id":"a","kind":"fee","amount_paise":1000000},
                       {"id":"b","kind":"payment","amount":2500},
                       {"id":"c","kind":"expense","amount_paise":"50000"}]}
            """)
        XCTAssertEqual(detail.updates, [])
        XCTAssertEqual(detail.chats, [])
        XCTAssertEqual(detail.courtHistory, [])
        XCTAssertNil(detail.linkedCase)
        XCTAssertEqual(detail.tasks, [])
        XCTAssertEqual(detail.people, [])
        XCTAssertEqual(detail.totals, MatterRules.LedgerTotals(billed: 10000, received: 2500, outstanding: 7500, expenses: 500))
    }

    /// The server's totals win wherever it sent them; a missing one is summed.
    func testPartialTotalsAreFilledFromTheLedger() throws {
        let detail = try decode("""
            {"success":true,"project":{"id":"p"},
             "ledger":[{"id":"a","kind":"expense","amount_paise":12345}],
             "totals":{"billed":100,"received":40}}
            """)
        XCTAssertEqual(detail.totals.billed, 100)
        XCTAssertEqual(detail.totals.received, 40)
        XCTAssertEqual(detail.totals.expenses, 123.45, accuracy: 0.0001)
    }

    /// One row that cannot be read costs only itself — the rest of the record stands.
    func testABrokenRowCostsOnlyItself() throws {
        let detail = try decode("""
            {"success":true,"project":{"id":"p"},
             "tasks":[{"title":"No id"},{"id":"t2","title":"Kept"}],
             "people":"not a list",
             "linkedCase":{"title":"No id"},
             "totals":"nonsense"}
            """)
        XCTAssertEqual(detail.tasks.map(\.id), ["t2"])
        XCTAssertEqual(detail.people, [])
        XCTAssertNil(detail.linkedCase)
        XCTAssertEqual(detail.totals, MatterRules.LedgerTotals(billed: 0, received: 0, outstanding: 0, expenses: 0))
    }

    /// The matter itself is what the answer is about: without a readable one, it is no answer.
    func testAnUnreadableMatterFailsTheDecode() {
        XCTAssertThrowsError(try JSONDecoder().decode(
            ProjectDetailResponse.self, from: Data(#"{"success":true,"project":{"name":"no id"}}"#.utf8)))
    }
}
