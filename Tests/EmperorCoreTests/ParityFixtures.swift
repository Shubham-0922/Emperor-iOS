import XCTest
@testable import EmperorCore

/// Reads `Resources/parity/<pkg>/<name>` — a golden fixture a parity package's
/// `scripts/generate-*-fixtures.mjs` wrote from the platform's own JavaScript. `name` may carry
/// its extension; without one, `.json` is assumed.
func parityFixture(_ pkg: String, _ name: String) throws -> Data {
    let file = name as NSString
    let resource = file.pathExtension.isEmpty ? name : file.deletingPathExtension
    let ext = file.pathExtension.isEmpty ? "json" : file.pathExtension
    let url = try XCTUnwrap(
        Bundle.module.url(forResource: resource, withExtension: ext, subdirectory: "parity/\(pkg)"),
        "missing fixture parity/\(pkg)/\(resource).\(ext) — run its scripts/generate-*-fixtures.mjs")
    return try Data(contentsOf: url)
}

/// The fixture folder is bundled, so a package's first fixture needs no change to `Package.swift`.
final class ParityFixturesTests: XCTestCase {

    func testTheParityFolderIsBundled() throws {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "README", withExtension: "txt", subdirectory: "parity"))
        XCTAssertFalse(try Data(contentsOf: url).isEmpty)
    }
}
