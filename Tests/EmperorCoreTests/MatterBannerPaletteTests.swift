import XCTest
@testable import EmperorCore

/// White text on a matter banner sits on the plate (`MatterBanner.plate`), never on the gradient
/// alone. These hold that the plate clears WCAG AA (4.5:1) over every point of every preset's
/// gradient — each end, and the lit corner — mixed with the card surface of both themes.
final class MatterBannerPaletteTests: XCTestCase {

    private let white = PaletteColor(1, 1, 1)
    private let surfaces: [(String, PaletteColor)] = [
        ("light", PaletteColor(hex: 0xFFFFFF)),
        ("dark", PaletteColor(hex: 0x1B1F36)),
    ]

    func testEveryPresetHasItsTwoStops() {
        XCTAssertEqual(Set(MatterBanner.presets.keys), Set(MatterVocabulary.BannerPreset.allCases))
    }

    func testWhiteTextOnThePlateClearsAAOverEveryPreset() {
        for preset in MatterVocabulary.BannerPreset.allCases {
            for (theme, surface) in surfaces {
                let stops = MatterBanner.gradient(preset, surface: surface)
                let backgrounds = [
                    ("start", stops.start),
                    ("end", stops.end),
                    ("lit corner", MatterBanner.highlight.composited(over: stops.start)),
                ]
                for (name, background) in backgrounds {
                    let plate = MatterBanner.plate.composited(over: background)
                    let ratio = white.contrastRatio(against: plate)
                    XCTAssertGreaterThanOrEqual(ratio, 4.5, "\(preset.rawValue) \(name), \(theme): \(ratio)")
                }
            }
        }
    }

    func testTheMixKeepsMostOfEachHue() {
        let navy = MatterBanner.gradient(.navy, surface: PaletteColor(hex: 0xFFFFFF))
        // #252A47 at 90 % over white: 0x25 → 0.9 * 37 + 0.1 * 255.
        XCTAssertEqual(navy.start.red * 255, 0.9 * 37 + 0.1 * 255, accuracy: 0.0001)
        XCTAssertEqual(MatterBanner.plate.opacity, 0.55)
    }

    func testEveryStatusHasADot() {
        XCTAssertEqual(Set(MatterBanner.statusDot.keys), Set(MatterVocabulary.ProjectStatus.allCases))
    }
}
