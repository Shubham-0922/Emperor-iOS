import SwiftUI

/// About & Compliance — what the build is and where Emperor lives: the version and the company,
/// the website and the two legal pages (their links land when the pages do), and the company's
/// own handles, each opening in the browser. Pushed from Settings; the same social rows sit at
/// the foot of the More tab.
struct AboutComplianceView: View {
    @Environment(\.theme) private var theme
    @Environment(\.openURL) private var openURL

    var body: some View {
        List {
            Section {
                ValueRow("Version", value: "v\(AppVersion.short) (\(AppVersion.build))")
                ValueRow("Developer", value: EmperorLinks.companyName)
            } header: {
                SectionHeader(title: "App")
            }
            .listRowBackground(theme.surface)

            Section {
                linkRow("Website", detail: "app.emperorailabs.com", opens: EmperorLinks.website)
                linkRow("Privacy Policy", detail: nil, opens: EmperorLinks.privacyPolicy)
                linkRow("Terms & Conditions", detail: nil, opens: EmperorLinks.terms)
            } header: {
                SectionHeader(title: "Legal")
            }
            .listRowBackground(theme.surface)

            Section {
                ForEach(EmperorLinks.socials) { social in
                    SocialLinkRow(social: social)
                }
            } header: {
                SectionHeader(title: "Follow Emperor")
            }
            .listRowBackground(theme.surface)
        }
        .font(.brand(.body))
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(theme.groupedBackground)
        .navigationTitle("About & Compliance")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("about-screen")
    }

    /// A row that leaves for a page when there is one to open, and stands in when there is not —
    /// the legal pages, until the platform has them.
    private func linkRow(_ title: String, detail: String?, opens url: URL?) -> some View {
        Button {
            if let url { openURL(url) }
        } label: {
            HStack(spacing: Spacing.sm) {
                Text(title)
                    .font(.brand(.body, weight: .medium))
                    .foregroundStyle(theme.textPrimary)
                    .dynamicLineLimit(2)
                Spacer(minLength: Spacing.sm)
                if let detail {
                    Text(detail)
                        .font(.brand(.footnote))
                        .foregroundStyle(theme.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Image(systemName: "arrow.up.right.square")
                    .font(.brand(.footnote, weight: .semibold))
                    .foregroundStyle(theme.textTertiary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(url == nil ? "Not available yet" : "Opens \(title) in your browser")
    }
}

/// One handle as a row: the platform's monogram tile, its name and what the account is called
/// there, and the glyph that says the row leaves for the browser. The same row heads the foot
/// of More, so the addresses cannot drift between the two screens.
struct SocialLinkRow: View {
    @Environment(\.theme) private var theme
    @Environment(\.openURL) private var openURL

    let social: SocialHandle

    var body: some View {
        Button {
            openURL(social.url)
        } label: {
            HStack(spacing: Spacing.sm) {
                // The document tile's letters, at home here as a platform monogram: this app
                // draws no brand logos, and the name beside them says which platform it is.
                DocumentTile(kind: social.monogram)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(social.name)
                        .font(.brand(.body, weight: .medium))
                        .foregroundStyle(theme.textPrimary)
                        .dynamicLineLimit(2)
                    Text(social.handle)
                        .font(.brand(.caption))
                        .foregroundStyle(theme.textTertiary)
                        .dynamicLineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "arrow.up.right.square")
                    .font(.brand(.footnote, weight: .semibold))
                    .foregroundStyle(theme.textTertiary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(social.name), \(social.handle)")
        .accessibilityHint("Opens \(social.name) in your browser")
        .accessibilityIdentifier("social-\(social.name)")
    }
}

/// The built app's version, read from the bundle — every screen that shows it shares one
/// answer, so a bug report can never name a different build than About does.
enum AppVersion {
    static var short: String { info["CFBundleShortVersionString"] as? String ?? "—" }
    static var build: String { info["CFBundleVersion"] as? String ?? "—" }

    private static var info: [String: Any] { Bundle.main.infoDictionary ?? [:] }
}
