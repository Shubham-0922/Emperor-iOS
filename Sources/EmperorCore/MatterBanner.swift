import Foundation

/// A matter's banner, as the web paints it (`src/components/projects/ProjectBanner.jsx`): one of
/// eight two-hue gradients, each end mixed a little with the card's own surface so the same
/// "wine" reads as wine on a white card and on a navy one. Nothing on a banner relies on the
/// gradient for contrast — text sits on `plate`, near-black glass, which also keeps it legible
/// over an uploaded photo (`MatterBannerPaletteTests` holds that for every preset and theme).
enum MatterBanner {

    typealias Preset = MatterVocabulary.BannerPreset

    /// `PRESETS`: [from, to] per preset.
    static let presets: [Preset: (from: UInt32, to: UInt32)] = [
        .navy: (0x252A47, 0x464E85),
        .slate: (0x343A4F, 0x6B7187),
        .indigo: (0x464E85, 0x8B95CC),
        .teal: (0x24555C, 0x6F9AC0),
        .forest: (0x22463A, 0x5C8569),
        .wine: (0x4A2034, 0x8B4A64),
        .gold: (0x6A4C14, 0xC29A48),
        .sand: (0x7E6E55, 0xD2C2A2),
    ]

    /// How much of each end's own hue survives the mix with the surface.
    static let fromShare = 0.90
    static let toShare = 0.78

    /// `color-mix(in srgb, hex share%, surface)`: a straight mix of the encoded components.
    static func mix(_ hex: UInt32, share: Double, with surface: PaletteColor) -> PaletteColor {
        let c = PaletteColor(hex: hex)
        return PaletteColor(c.red * share + surface.red * (1 - share),
                            c.green * share + surface.green * (1 - share),
                            c.blue * share + surface.blue * (1 - share))
    }

    /// The gradient's two stops (drawn at 135°) on a given card surface.
    static func gradient(_ preset: Preset, surface: PaletteColor) -> (start: PaletteColor, end: PaletteColor) {
        let stops = presets[preset] ?? presets[.navy]!
        return (mix(stops.from, share: fromShare, with: surface), mix(stops.to, share: toShare, with: surface))
    }

    /// The lit top-left corner laid over the gradient (`rgba(255,255,255,.16)` fading out).
    static let highlight = PaletteColor.white(0.16)

    /// The plate every overlay sits on: `rgba(12, 14, 28, .55)`, white text.
    static let plate = PaletteColor(hex: 0x0C0E1C, opacity: 0.55)

    /// The plate's hairline: `rgba(255, 255, 255, .16)`.
    static let plateBorder = PaletteColor.white(0.16)

    /// `STATUS_DOT` of the workspace header.
    static let statusDot: [MatterVocabulary.ProjectStatus: UInt32] = [
        .active: 0x4ADE80, .onHold: 0xFBBF24, .disposed: 0xCBD5E1, .archived: 0x94A3B8,
    ]
}
