import PhotosUI
import SwiftUI
import UIKit

/// Settings → Send feedback: a bug report or a note, with optional screenshots.
///
/// The rules (what counts as empty, the screenshot cap, how a 413 reads) live in the core's
/// `FeedbackService`; this lays out the form and compresses each picked image to a small JPEG
/// with the same search the image tool uses.
struct SupportFeedbackView: View {
    @Environment(Session.self) private var session
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var kind: SupportFeedbackKind = .feedback
    @State private var message = ""
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var screenshots: [SupportScreenshot] = []
    @State private var isSending = false
    @State private var errorText: String?
    @State private var didSend = false

    private var canSend: Bool {
        !isSending && !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        List {
            Section {
                Picker("Type", selection: $kind) {
                    ForEach(SupportFeedbackKind.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(theme.surface)
            }

            Section {
                TextEditor(text: $message)
                    .frame(minHeight: 140)
                    .font(.brand(.body))
                    .accessibilityLabel("Description")
                    .accessibilityIdentifier("support-description")
                    .listRowBackground(theme.surface)
            } header: {
                SectionHeader(title: "What happened?")
            }

            Section {
                PhotosPicker(
                    selection: $pickerItems,
                    maxSelectionCount: SupportFeedbackLimits.maxScreenshots,
                    matching: .images
                ) {
                    IconRowLabel(
                        title: screenshots.isEmpty
                            ? "Attach screenshots" : "\(screenshots.count) attached",
                        systemImage: "photo.on.rectangle")
                }
                .listRowBackground(theme.surface)
                if !screenshots.isEmpty {
                    Button("Remove screenshots", role: .destructive) {
                        screenshots = []
                        pickerItems = []
                    }
                    .listRowBackground(theme.surface)
                }
            } header: {
                SectionHeader(title: "Screenshots (optional)")
            }

            if let errorText {
                Section {
                    Text(errorText)
                        .font(.brand(.callout))
                        .foregroundStyle(.red)
                        .listRowBackground(theme.surface)
                }
            }

            Section {
                Button {
                    Task { await send() }
                } label: {
                    HStack {
                        if isSending { ProgressView() }
                        Text(isSending ? "Sending…" : "Send")
                    }
                    .frame(maxWidth: .infinity)
                }
                .disabled(!canSend)
                .accessibilityIdentifier("support-send")
                .listRowBackground(theme.surface)
            }
        }
        .font(.brand(.body))
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(theme.groupedBackground)
        .navigationTitle("Send feedback")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: pickerItems) { _, items in
            Task { await load(items) }
        }
        .alert("Thank you", isPresented: $didSend) {
            Button("OK") { dismiss() }
        } message: {
            Text("Your message was sent.")
        }
    }

    private func load(_ items: [PhotosPickerItem]) async {
        var loaded: [SupportScreenshot] = []
        for (index, item) in items.enumerated() {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let jpeg = Self.compress(data) else { continue }
            loaded.append(SupportScreenshot(data: jpeg, fileName: "screenshot-\(index + 1).jpg"))
        }
        screenshots = loaded
    }

    private func send() async {
        errorText = nil
        isSending = true
        defer { isSending = false }
        do {
            try await FeedbackService(client: session.client).submitSupportFeedback(
                kind: kind, description: message, screenshots: screenshots,
                pageURL: "ios:settings")
            didSend = true
        } catch {
            errorText = error.localizedDescription
        }
    }

    /// Re-encodes to a JPEG near `screenshotTargetBytes` using the shared search.
    private static func compress(_ data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let width = max(1, Int((image.size.width * image.scale).rounded()))
        let height = max(1, Int((image.size.height * image.scale).rounded()))
        let result = try? ImageCompression.search(
            width: width, height: height, targetBytes: SupportFeedbackLimits.screenshotTargetBytes
        ) { w, h, quality in
            autoreleasepool {
                let size = CGSize(width: w, height: h)
                let format = UIGraphicsImageRendererFormat()
                format.scale = 1
                format.opaque = true
                let drawn = UIGraphicsImageRenderer(size: size, format: format).image { context in
                    UIColor.white.setFill()
                    context.fill(CGRect(origin: .zero, size: size))
                    image.draw(in: CGRect(origin: .zero, size: size))
                }
                return drawn.jpegData(compressionQuality: quality)
            }
        }
        return result?.data
    }
}
