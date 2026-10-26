import XCTest
@testable import EmperorCore

/// The colour pairings the analysis screens add, held to AA as `PaletteTests` holds the rest: the
/// report's notes and the limitation watch on the warning wash, the year row's highlight on the
/// accent wash, the fix on the success wash, the chart's year chip, and the secondary text of each.
final class AnalysisPaletteTests: XCTestCase {

    private let cases: [(name: String, palette: Palette)] = [("dark", .dark), ("light", .light)]

    func testTheAnalysisWashesKeepTheirWordsReadable() {
        for (name, palette) in cases {
            let washes: [(String, PaletteColor)] = [
                ("warnBg", palette.record.warnBg),
                ("accentSoft", palette.record.accentSoft),
                ("successBg", palette.record.successBg),
                ("dangerBg", palette.record.dangerBg),
            ]
            for (washName, wash) in washes {
                for (surfaceName, surface) in [("canvas", palette.canvas), ("surface", palette.surface)] {
                    let fill = wash.composited(over: surface)
                    for (text, colour) in [("primary", palette.textPrimary), ("secondary", palette.textSecondary)] {
                        let ratio = colour.contrastRatio(against: fill)
                        XCTAssertGreaterThanOrEqual(
                            ratio, 4.5,
                            "\(name)/\(washName) on \(surfaceName): \(text) is \(String(format: "%.2f", ratio)):1")
                    }
                }
            }
            // The Doc Index table's alternate rows.
            let striped = palette.textSecondary.contrastRatio(against: palette.record.surface2)
            XCTAssertGreaterThanOrEqual(striped, 4.5, "\(name): secondary text on a striped row")
            let chip = palette.record.onInverse.contrastRatio(against: palette.record.inverse)
            XCTAssertGreaterThanOrEqual(chip, 4.5, "\(name): the year chip")
        }
    }
}
