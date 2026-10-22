import Foundation

/// Where Emperor lives on the web — what About & Compliance and the More tab link out to.
///
/// The social addresses are the company's own, held here so the two screens that show them can
/// never drift apart, and checkable on any platform (`EmperorLinksTests`). The two legal pages
/// do not exist on the platform yet: their URLs are `nil` until they do, and the rows stay
/// drawn — the stand-in the More tab's case-tool cards are — rather than pointing at a page
/// that is not there.
enum EmperorLinks {
    /// The app itself, where a signed-in account works in the browser. A literal, so the
    /// force-unwrap can never fail.
    static let website = URL(string: "https://app.emperorailabs.com")!
    /// Added the moment the pages exist; until then their rows stand in.
    static let privacyPolicy: URL? = nil
    static let terms: URL? = nil
    /// The company the app is built for and by — the About screen's developer line.
    static let companyName = "Emperor AI Labs"

    /// The handles, in the order About & Compliance lists them.
    static let socials: [SocialHandle] = [
        SocialHandle(
            name: "YouTube", handle: "@emperorailabs", monogram: "YT",
            url: URL(string: "https://youtube.com/@emperorailabs")!),
        SocialHandle(
            name: "Facebook", handle: "Emperor AI", monogram: "FB",
            url: URL(string: "https://www.facebook.com/people/Emperor-AI/61594877455888/")!),
        SocialHandle(
            name: "LinkedIn", handle: "Emperor AI Labs", monogram: "IN",
            url: URL(string: "https://www.linkedin.com/company/emperor-ai-labs")!),
        SocialHandle(
            name: "X", handle: "@emperorailabs", monogram: "X",
            url: URL(string: "https://x.com/emperorailabs")!),
        SocialHandle(
            name: "Instagram", handle: "@emperorailabs", monogram: "IG",
            url: URL(string: "https://www.instagram.com/emperorailabs")!),
    ]
}

/// One social platform: its display name, what the account is called there, the letters that
/// head its row, and the page to open.
struct SocialHandle: Identifiable, Equatable, Sendable {
    let name: String
    let handle: String
    /// The tile's letters — "YT", "IN", "IG" — uppercased where they are drawn.
    let monogram: String
    let url: URL

    var id: String { name }
}
