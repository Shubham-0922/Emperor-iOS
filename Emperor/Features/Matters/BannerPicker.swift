import SwiftUI

/// The eight banner presets as pickable tiles — each the real banner, small, so what is picked is
/// what the matter wears (`BannerPresetPicker`, `shared.jsx`). Each is a button named for its
/// preset and marked selected for VoiceOver.
struct BannerPicker: View {
    @Environment(\.theme) private var theme

    /// The chosen preset; nil while the banner is an uploaded picture.
    let selected: MatterVocabulary.BannerPreset?
    let onPick: (MatterVocabulary.BannerPreset) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 52), spacing: Spacing.sm)], alignment: .leading,
                  spacing: Spacing.sm) {
            ForEach(MatterVocabulary.BannerPreset.allCases, id: \.self) { preset in
                let isOn = preset == selected
                Button {
                    onPick(preset)
                } label: {
                    MatterBannerView(preset: preset, cornerRadius: Radius.small) {
                        if isOn {
                            Image(systemName: "checkmark")
                                .font(.system(size: 13, weight: .heavy))
                                .foregroundStyle(Color.white)
                                .shadow(color: Color.black.opacity(0.45), radius: 1, y: 1)
                        }
                    }
                    .frame(height: 30)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.small + 2, style: .continuous)
                            .strokeBorder(isOn ? theme.accent : Color.clear, lineWidth: 2)
                            .padding(-3))
                    .frame(minHeight: Layout.touchTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(preset.label) banner")
                .accessibilityAddTraits(isOn ? .isSelected : [])
                .accessibilityIdentifier("banner-\(preset.rawValue)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Banner")
    }
}

/// The folder colours plus None, each named — the dot alone is information a colour-blind reader
/// cannot use (`ColourSwatches`, `shared.jsx`). A colour is shown by the banner preset nearest it,
/// so the swatch is the hue the matter's banner falls back to.
struct ColourSwatches: View {
    @Environment(\.theme) private var theme

    /// A colour key, or nil for none.
    let selected: String?
    let onPick: (String?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.sm) {
                    swatch(nil)
                    ForEach(MatterVocabulary.ProjectColor.allCases, id: \.self) { colour in
                        swatch(colour)
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 2)
            }
            Text(MatterVocabulary.ProjectColor.label(of: selected).replacingOccurrences(of: "No colour", with: "None"))
                .font(.brand(.caption))
                .foregroundStyle(theme.textTertiary)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Folder colour")
    }

    private func swatch(_ colour: MatterVocabulary.ProjectColor?) -> some View {
        let isOn = MatterVocabulary.ProjectColor.normalize(selected) == colour
        let label = colour?.label ?? "No colour"
        return Button {
            onPick(colour?.rawValue)
        } label: {
            ZStack {
                if let colour {
                    MatterBannerView(
                        preset: MatterMeta.bannerPreset(banner: nil, color: colour.rawValue), cornerRadius: 13)
                } else {
                    Circle()
                        .fill(theme.surface2)
                        .overlay(Circle().strokeBorder(theme.borderStrong, lineWidth: 1))
                    Image(systemName: "nosign")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.textTertiary)
                }
            }
            .frame(width: 26, height: 26)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(isOn ? theme.accent : Color.clear, lineWidth: 2).padding(-3))
            .frame(minWidth: Layout.touchTarget, minHeight: Layout.touchTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
