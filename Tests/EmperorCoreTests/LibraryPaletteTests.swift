import XCTest
@testable import EmperorCore

/// The Library's own colours: the cream lettering on every cover cloth, and each collection's and
/// court's ink where the app draws it as text — on the card surface of each theme.
final class LibraryPaletteTests: XCTestCase {

    func testCoverLetteringClearsAAOnEveryCloth() {
        let ink = LibraryDisplay.color(LibraryDisplay.coverInk)
        for cloth in LibraryDisplay.allCloths {
            let ratio = ink.contrastRatio(against: LibraryDisplay.color(cloth))
            XCTAssertGreaterThanOrEqual(ratio, 4.5, "cream on \(cloth) is \(String(format: "%.2f", ratio)):1")
        }
    }

    func testCollectionAndCourtInkClearsAAOnTheCardSurface() {
        var inks: [(String, String, String)] = LibraryCategoryKey.order.map {
            let t = LibraryDisplay.theme($0)
            return ($0, t.ink, t.inkDark)
        }
        inks += LibraryDisplay.courtOrder.map {
            let c = LibraryDisplay.courtInfo($0)
            return ($0, c.ink, c.inkDark)
        }
        let unknown = LibraryDisplay.courtInfo("orissa", label: "Orissa High Court")
        inks.append(("unknown court", unknown.ink, unknown.inkDark))
        for (name, light, dark) in inks {
            for (theme, palette, hex) in [("light", Palette.light, light), ("dark", Palette.dark, dark)] {
                for surface in [palette.surface, palette.canvas] {
                    let ratio = LibraryDisplay.color(hex).contrastRatio(against: surface)
                    XCTAssertGreaterThanOrEqual(ratio, 4.5, "\(name) ink on the \(theme) surface is \(String(format: "%.2f", ratio)):1")
                }
            }
        }
    }
}
