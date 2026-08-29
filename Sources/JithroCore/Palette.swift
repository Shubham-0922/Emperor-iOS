import Foundation

/// Which appearance the app uses.
///
/// **Dark is the default**, deliberately — not "follow the system". The product is read in
/// courtrooms and corridors, and the platform's own dashboard is dark. A user who prefers
/// otherwise can say so; a user who never opens Settings gets the intended look.
enum ThemePreference: String, CaseIterable, Sendable, Codable {
    case dark, light, system

    static let `default` = ThemePreference.dark

    var label: String {
        switch self {
        case .dark: return "Dark"
        case .light: return "Light"
        case .system: return "Match device"
        }
    }

    static let storageKey = "appearance.preference.v1"
}

/// One colour, as sRGB components in 0...1.
///
/// Deliberately not `SwiftUI.Color`: the palette lives in the Foundation-only core so its
/// contrast ratios can be *tested* rather than eyeballed. The app layer maps these to `Color`
/// in one place.
struct PaletteColor: Equatable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var opacity: Double

    init(_ red: Double, _ green: Double, _ blue: Double, opacity: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.opacity = opacity
    }

    /// From a `#RRGGBB` hex, which is how the values were read off the platform.
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            Double((hex >> 16) & 0xFF) / 255,
            Double((hex >> 8) & 0xFF) / 255,
            Double(hex & 0xFF) / 255,
            opacity: opacity)
    }

    /// White at a given alpha — the surface ladder the platform's dashboard is built from.
    static func white(_ opacity: Double) -> PaletteColor {
        PaletteColor(1, 1, 1, opacity: opacity)
    }

    static func black(_ opacity: Double) -> PaletteColor {
        PaletteColor(0, 0, 0, opacity: opacity)
    }

    /// Relative luminance, per WCAG 2.1.
    var luminance: Double {
        func channel(_ value: Double) -> Double {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }

    /// This colour composited over an opaque background, so a translucent surface can be
    /// measured for contrast the way it will actually be seen.
    func composited(over background: PaletteColor) -> PaletteColor {
        guard opacity < 1 else { return self }
        let a = opacity
        return PaletteColor(
            red * a + background.red * (1 - a),
            green * a + background.green * (1 - a),
            blue * a + background.blue * (1 - a))
    }

    /// WCAG contrast ratio against another colour, 1...21.
    func contrastRatio(against other: PaletteColor) -> Double {
        let a = luminance
        let b = other.luminance
        let lighter = max(a, b)
        let darker = min(a, b)
        return (lighter + 0.05) / (darker + 0.05)
    }
}

/// The app's colours, for one appearance.
///
/// Taken from the platform so the two products read as one. The accent, the status colours and
/// the surface ladder are the values the marketing dashboard actually renders (measured from
/// `emperorailabs.com`); the navy-charcoal surfaces are the app's own `s2-dark` tokens
/// (`src/index.css`).
struct Palette: Sendable {

    // MARK: Surfaces
    /// Behind everything.
    var canvas: PaletteColor
    /// Cards, list rows, sheets.
    var surface: PaletteColor
    /// A card on a card — pickers, the composer, a raised panel.
    var surfaceElevated: PaletteColor
    /// A faint tint used for panels that should read as "ours" rather than neutral.
    var surfaceAccent: PaletteColor
    var separator: PaletteColor

    // MARK: Text
    var textPrimary: PaletteColor
    var textSecondary: PaletteColor
    var textTertiary: PaletteColor
    /// Text drawn on top of `accent`.
    var onAccent: PaletteColor

    // MARK: Accent
    var accent: PaletteColor
    /// The accent as a *text* colour, lightened on dark so it stays legible.
    var accentText: PaletteColor
    var accentMuted: PaletteColor

    // MARK: Status
    var success: PaletteColor
    var warning: PaletteColor
    var danger: PaletteColor
    var info: PaletteColor

    /// Dark — the default.
    ///
    /// Surfaces are the platform's `s2-dark` navy-charcoal; accent and status are measured from
    /// the dashboard in the marketing hero.
    static let dark = Palette(
        canvas: PaletteColor(hex: 0x141824),
        surface: PaletteColor(hex: 0x1E2535),
        surfaceElevated: PaletteColor(hex: 0x252C3D),
        surfaceAccent: PaletteColor(hex: 0x96A3FF, opacity: 0.05),
        separator: .white(0.10),

        textPrimary: .white(0.94),
        textSecondary: .white(0.66),
        textTertiary: .white(0.44),
        onAccent: .white(1),

        // The platform's dashboard fills this button with `#6070E4`, which puts a white label
        // at 4.26:1 — below AA for body text. Darkened to the nearest value that clears 4.5:1
        // while reading as the same indigo.
        accent: PaletteColor(hex: 0x5A68D8),
        accentText: PaletteColor(hex: 0xB9C1FF),
        accentMuted: PaletteColor(hex: 0x6070E4, opacity: 0.18),

        success: PaletteColor(hex: 0x4FC38F),
        warning: PaletteColor(hex: 0xE0B45C),
        danger: PaletteColor(hex: 0xE79485),
        info: PaletteColor(hex: 0x7FB6DE))

    /// Light.
    ///
    /// Not an inversion. The status hues are the platform's own light-theme values
    /// (`s2-light`), which are darkened to hold contrast on a pale surface, and the accent is
    /// deepened for the same reason — `#6070E4` on white is legible for a fill but not for text.
    static let light = Palette(
        canvas: PaletteColor(hex: 0xF4F2F6),
        surface: PaletteColor(hex: 0xFFFFFF),
        surfaceElevated: PaletteColor(hex: 0xFAF8FC),
        surfaceAccent: PaletteColor(hex: 0x6070E4, opacity: 0.05),
        separator: PaletteColor(hex: 0x3A2A36, opacity: 0.14),

        textPrimary: PaletteColor(hex: 0x2E2833),
        textSecondary: PaletteColor(hex: 0x5F5766),
        textTertiary: PaletteColor(hex: 0x3A333E, opacity: 0.58),
        onAccent: .white(1),

        accent: PaletteColor(hex: 0x4B58C8),
        accentText: PaletteColor(hex: 0x3B47AD),
        accentMuted: PaletteColor(hex: 0x4B58C8, opacity: 0.12),

        success: PaletteColor(hex: 0x2C6B49),
        warning: PaletteColor(hex: 0x7E5F16),
        danger: PaletteColor(hex: 0x9C2B25),
        info: PaletteColor(hex: 0x3F5D7D))

    static func palette(for appearance: ThemePreference, systemIsDark: Bool) -> Palette {
        switch appearance {
        case .dark: return .dark
        case .light: return .light
        case .system: return systemIsDark ? .dark : .light
        }
    }
}
