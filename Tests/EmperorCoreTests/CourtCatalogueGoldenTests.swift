import XCTest
@testable import EmperorCore

/// `CourtCatalogue` held to the platform's `src/lib/courts.js`
/// (`scripts/generate-lookup-fixtures.mjs` → `court-catalogue.json`): the courts, their order and
/// names, the published case types and benches, and the High Court state codes. A change on the
/// web fails here instead of drifting. Regenerate on a platform change; never edit.
final class CourtCatalogueGoldenTests: XCTestCase {

    private struct Fixture: Decodable {
        struct Entry: Decodable { var id: String; var name: String; var category: String }
        var courts: [Entry]
        var scCaseTypes: [CourtOption]
        var ncltBenches: [CourtOption]
        var ncltCaseTypes: [CourtOption]
        var nclatBenches: [CourtOption]
        var nclatCaseTypes: [CourtOption]
        var hcStateCode: [String: String]
    }

    private func load() throws -> Fixture {
        try JSONDecoder().decode(Fixture.self, from: try parityFixture("06-C", "court-catalogue"))
    }

    /// The web's `category` for each family — NCLT and NCLAT are tribunals there.
    private func category(_ family: CourtFamily) -> String {
        switch family {
        case .supremeCourt: return "sc"
        case .highCourt: return "hc"
        case .districtCourt: return "district"
        case .nclt, .nclat, .tribunal: return "tribunal"
        case .consumerForum: return "forum"
        }
    }

    func testEveryCourtInThePlatformsOrder() throws {
        let f = try load()
        XCTAssertEqual(CourtCatalogue.all.map(\.id), f.courts.map(\.id))
        for (ours, theirs) in zip(CourtCatalogue.all, f.courts) {
            XCTAssertEqual(ours.name, theirs.name, ours.id)
            XCTAssertEqual(category(ours.family), theirs.category, ours.id)
        }
    }

    func testThePublishedListsMatch() throws {
        let f = try load()
        XCTAssertEqual(CourtCatalogue.supremeCourtCaseTypes, f.scCaseTypes)
        XCTAssertEqual(CourtCatalogue.ncltBenches, f.ncltBenches)
        XCTAssertEqual(CourtCatalogue.ncltCaseTypes, f.ncltCaseTypes)
        XCTAssertEqual(CourtCatalogue.nclatBenches, f.nclatBenches)
        XCTAssertEqual(CourtCatalogue.nclatCaseTypes, f.nclatCaseTypes)
    }

    func testEveryHighCourtStateCodeMatches() throws {
        let f = try load()
        XCTAssertEqual(f.hcStateCode.count, CourtSearchQuery.highCourtIDsByStateCode.count)
        for (id, code) in f.hcStateCode {
            XCTAssertEqual(CourtSearchQuery.stateCode(forHighCourtID: id), code, id)
            XCTAssertEqual(CourtSearchQuery.highCourtID(forStateCode: code), id, code)
        }
    }
}
