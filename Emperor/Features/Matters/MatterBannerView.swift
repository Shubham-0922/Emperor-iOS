import SwiftUI
import UIKit

/// A matter's banner, as the web paints it (`ProjectBanner.jsx`, ported in `MatterBanner`): one of
/// eight two-hue gradients mixed with the card's surface, lit at the top-left — or the matter's
/// own uploaded picture over it. Anything drawn on it sits on `MatterBanner.plate`, near-black
/// glass, so white text stays legible on every preset and every photograph.
///
/// Decorative: the row or header it sits in says what the matter is.
struct MatterBannerView<Overlay: View>: View {
    @Environment(\.theme) private var theme

    let preset: MatterVocabulary.BannerPreset
    /// An uploaded picture's bytes; nil draws the preset.
    var imageData: Data?
    var cornerRadius: CGFloat = Radius.control
    @ViewBuilder var overlay: () -> Overlay

    var body: some View {
        let stops = MatterBanner.gradient(preset, surface: theme.palette.surface)
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            LinearGradient(
                colors: [Color(stops.start), Color(stops.end)],
                startPoint: .topLeading, endPoint: .bottomTrailing)
            LinearGradient(
                colors: [Color(MatterBanner.highlight), Color.clear],
                startPoint: .topLeading, endPoint: .center)
            if let imageData, let image = UIImage(data: imageData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .accessibilityHidden(true)
            }
            overlay()
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(theme.separator, lineWidth: 1))
    }
}

extension MatterBannerView where Overlay == EmptyView {
    init(preset: MatterVocabulary.BannerPreset, imageData: Data? = nil, cornerRadius: CGFloat = Radius.control) {
        self.init(preset: preset, imageData: imageData, cornerRadius: cornerRadius) { EmptyView() }
    }
}

/// White words on the banner's plate — the practice area on a card, a fact in the header.
struct MatterBannerPlate<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .foregroundStyle(Color.white)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(
                Color(MatterBanner.plate),
                in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                    .strokeBorder(Color(MatterBanner.plateBorder), lineWidth: 1))
    }
}
