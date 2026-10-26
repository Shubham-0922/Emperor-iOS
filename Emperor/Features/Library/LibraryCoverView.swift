import SwiftUI
import UIKit

/// The cover loader the Library's screens share, handed down from `LibraryView`.
private struct LibraryCoversKey: EnvironmentKey {
    static let defaultValue: LibraryCoverLoader? = nil
}

extension EnvironmentValues {
    var libraryCovers: LibraryCoverLoader? {
        get { self[LibraryCoversKey.self] }
        set { self[LibraryCoversKey.self] = newValue }
    }
}

/// A document's cover, as the web's `Cover.jsx` draws it: the collection's cloth (the same in
/// both themes — a red book is red in a dark room), a darker spine, a gilt rule, the kicker in
/// small capitals and the title in the display serif, in cream lettering `LibraryPaletteTests`
/// holds to 4.5:1 on every cloth. For a PDF the first page (or a real front cover) fades in over
/// it once the loader has it; a document marked `cover: none`, or one with no image, keeps the
/// typographic cover.
///
/// Decorative: the card beside it carries the title and the facts for VoiceOver. Drawn at the
/// default text size whatever the reader's, because it is a picture of a book, not text to read.
struct LibraryCoverView: View {
    @Environment(\.libraryCovers) private var covers
    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let doc: LibraryDoc
    var width: CGFloat = 110
    var showsImage = true

    @State private var image: UIImage?

    private var cream: Color { Color(LibraryDisplay.color(LibraryDisplay.coverInk)) }
    private var gilt: Color { Color(LibraryDisplay.color(LibraryDisplay.coverGilt)) }

    var body: some View {
        let height = width * 4 / 3
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color(LibraryDisplay.color(LibraryDisplay.cloth(for: doc))))
            face
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: width, height: height)
                    .clipped()
                    .transition(.opacity)
            }
            // The spine, over the image too, so a scanned page still reads as a bound book.
            LinearGradient(
                colors: [Color.black.opacity(0.28), Color.black.opacity(0)],
                startPoint: .leading, endPoint: .trailing)
                .frame(width: max(4, width * 0.07))
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        .shadow(color: Color.black.opacity(0.18), radius: 2, x: 0, y: 1)
        .dynamicTypeSize(.large)
        .accessibilityHidden(true)
        .task(id: doc.id) { await loadImage() }
    }

    private var lines: (kicker: String, title: String, foot: String) {
        if doc.category == LibraryCategoryKey.bareActs.rawValue {
            let split = LibraryDisplay.splitTitle(doc)
            return (LibraryDisplay.actKicker(doc), split.name, split.year)
        }
        let fields = LibraryDisplay.coverFields(doc)
        let title = fields.parties.map { "\($0[0]) v. \($0[1])" } ?? fields.title ?? ""
        return (fields.kicker, title, fields.foot.joined(separator: " · "))
    }

    private var face: some View {
        let l = lines
        return VStack(alignment: .leading, spacing: width * 0.04) {
            Text(l.kicker.uppercased())
                .font(.brand(size: max(7, width * 0.07), weight: .semibold, relativeTo: .caption2))
                .tracking(0.6)
                .lineLimit(1)
            Rectangle()
                .fill(gilt)
                .frame(height: 1)
            Text(l.title)
                .font(.display(size: max(10, width * 0.125), relativeTo: .caption))
                .lineLimit(width < 80 ? 3 : 6)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
            if !l.foot.isEmpty {
                Text(l.foot)
                    .font(.brand(size: max(7, width * 0.07), weight: .medium, relativeTo: .caption2))
                    .lineLimit(1)
            }
        }
        .foregroundStyle(cream)
        .padding(.leading, max(6, width * 0.12))
        .padding(.trailing, max(4, width * 0.07))
        .padding(.vertical, max(5, width * 0.08))
        .frame(width: width, height: width * 4 / 3, alignment: .topLeading)
    }

    private func loadImage() async {
        guard showsImage, let covers, doc.coverWanted else { return }
        let pixels = LibraryCovers.width(forPoints: Double(width), scale: Double(displayScale))
        guard let data = await covers.image(for: doc, width: pixels), let loaded = UIImage(data: data) else { return }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.28)) {
            image = loaded
        }
    }
}
