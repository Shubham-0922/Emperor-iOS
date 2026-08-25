import SwiftUI

struct ChatThreadView: View {
    @Environment(Session.self) private var session

    @State private var model: ChatViewModel?
    @State private var draft = ""
    @State private var isScanning = false
    @State private var isBrowsingFiles = false
    @State private var scanError: String?
    @State private var openSource: OpenSource?
    @State private var citationError: String?
    /// Loaded lazily on the first citation tap. The whole tree is an expensive read, so it is
    /// not fetched until something actually needs it, and then reused.
    @State private var libraryCache: [FileNode.StoredFile] = []

    private struct OpenSource: Identifiable {
        let id = UUID()
        let attachment: ChatAttachment
        let mention: AnnexureMention
    }

    let chatID: String

    var body: some View {
        Group {
            if let model {
                thread(model)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Conversation")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard model == nil else { return }
            let created = ChatViewModel(chatID: chatID, service: session.chats)
            // `preferred_model` seeds the picker only — the per-request model is what the
            // server actually honours, so it is sent explicitly on every turn regardless.
            created.model = ChatModel.fromPreference(session.currentUser?.preferredModel)
            model = created
            await created.load()
        }
    }

    private func thread(_ model: ChatViewModel) -> some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(model.messages) { message in
                            // Explicit labels rather than trailing closures: both of these
                            // structs carry a private @State property, so the synthesised
                            // memberwise initialiser has a parameter after this one and
                            // trailing-closure matching gets subtle. Naming it is unambiguous.
                            MessageBubble(
                                message: message,
                                onSelectCitation: { showSource($0, in: model) })
                                .id(message.stableID)
                        }

                        // Above the answer, as in the web client: it explains the work the
                        // answer below is about to rest on.
                        if model.isStreaming || !model.progress.isEmpty {
                            ReasoningPanel(
                                snapshot: model.progress,
                                isStreaming: model.isStreaming,
                                liveStatus: model.status)
                        }

                        if let live = model.live {
                            AnswerView(
                                content: live,
                                isStreaming: true,
                                onSelectCitation: { showSource($0, in: model) })
                                .id("live")
                        }

                        if model.wasInterrupted {
                            Notice(
                                icon: "exclamationmark.triangle",
                                text: "This answer was interrupted before it finished. Nothing above has been lost — send again to have it completed.",
                                tint: .orange)
                        }

                        if let busy = model.busyNotice {
                            Notice(icon: "clock", text: busy, tint: .secondary)
                        }
                    }
                    .padding()
                }
                .onChange(of: model.live?.prose) { scrollToBottom(proxy, model) }
                .onChange(of: model.messages.count) { scrollToBottom(proxy, model) }
            }

            composer(model)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                settingsMenu(model)
            }
        }
        .alert("Scan failed", isPresented: .constant(scanError != nil)) {
            Button("OK") { scanError = nil }
        } message: {
            Text(scanError ?? "")
        }
        .sheet(isPresented: $isScanning) {
            DocumentScannerView { result in
                isScanning = false
                handleScan(result, into: model)
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $isBrowsingFiles) {
            FileLibraryView(alreadyAttached: model.attachments) { chosen in
                model.attachments = chosen
            }
        }
        .sheet(item: $openSource) { source in
            SourceDocumentView(attachment: source.attachment, mention: source.mention)
        }
        .alert("Cannot open that source", isPresented: .constant(citationError != nil)) {
            Button("OK") { citationError = nil }
        } message: {
            Text(citationError ?? "")
        }
    }

    /// Mode and persona.
    ///
    /// Both are per-request and neither is plan-gated — a Lite account may select Thinking,
    /// which the platform is explicit about being a default rather than a restriction.
    private func settingsMenu(_ model: ChatViewModel) -> some View {
        Menu {
            Picker("Mode", selection: Binding(
                get: { model.model },
                set: { model.model = $0 }
            )) {
                ForEach(ChatModel.allCases) { choice in
                    Text("\(choice.label) — \(choice.detail)").tag(choice)
                }
            }

            Picker("Acting as", selection: Binding(
                get: { model.role },
                set: { model.role = $0 }
            )) {
                ForEach(ChatRole.allCases) { choice in
                    Text(choice.label).tag(choice)
                }
            }
        } label: {
            Label(model.model.label, systemImage: "slider.horizontal.3")
        }
        .disabled(model.isStreaming)
    }

    private func composer(_ model: ChatViewModel) -> some View {
        VStack(spacing: 8) {
            if !model.attachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(model.attachments, id: \.name) { attachment in
                            Button {
                                model.attachments.removeAll { $0 == attachment }
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "doc")
                                    Text(attachment.name.replacingOccurrences(of: "_", with: " "))
                                        .lineLimit(1)
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(.quaternary, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
            }

            HStack(spacing: 10) {
                Menu {
                    Button {
                        isBrowsingFiles = true
                    } label: {
                        Label("Attach from documents", systemImage: "folder")
                    }
                    Button {
                        isScanning = true
                    } label: {
                        Label("Scan a paperbook", systemImage: "doc.viewfinder")
                    }
                } label: {
                    Image(systemName: "plus.circle")
                        .font(.title3)
                }
                .disabled(model.isStreaming)

                TextField("Ask about this matter…", text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .textFieldStyle(.roundedBorder)

                if model.isStreaming {
                    Button {
                        model.stop()
                    } label: {
                        Image(systemName: "stop.circle.fill").font(.title2)
                    }
                } else {
                    Button {
                        model.send(draft)
                        draft = ""
                    } label: {
                        Image(systemName: "arrow.up.circle.fill").font(.title2)
                    }
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .background(.bar)
    }

    /// Opens the document a citation points at, at the page it names.
    ///
    /// Resolution is two-stage: the turn's own attachments first, which needs no network,
    /// and only then the full library — because a citation from an earlier turn may name a
    /// file no longer attached to the composer.
    private func showSource(_ mention: AnnexureMention, in model: ChatViewModel) {
        if let attachment = CitationResolver.resolve(
            mention, attachments: model.attachments, files: libraryCache) {
            openSource = OpenSource(attachment: attachment, mention: mention)
            return
        }

        Task {
            if libraryCache.isEmpty, let tree = try? await session.files.tree() {
                libraryCache = FileService.allFiles(in: tree)
            }
            if let attachment = CitationResolver.resolve(
                mention, attachments: model.attachments, files: libraryCache) {
                openSource = OpenSource(attachment: attachment, mention: mention)
            } else {
                // Say which file is missing by name. A citation naming a document that is no
                // longer in the library is exactly the case the user needs told plainly.
                citationError = """
                \(mention.fileName.replacingOccurrences(of: "_", with: " ")) is not in your \
                document library any more, so its cited page cannot be opened.
                """
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, _ model: ChatViewModel) {
        let target = model.live != nil ? "live" : model.messages.last?.stableID
        guard let target else { return }
        withAnimation(.easeOut(duration: 0.15)) {
            proxy.scrollTo(target, anchor: .bottom)
        }
    }

    private func handleScan(_ result: Result<ScannedDocument, Error>, into model: ChatViewModel) {
        switch result {
        case .failure(let error):
            scanError = error.localizedDescription
        case .success(let document):
            Task {
                do {
                    let folder = "Scans"
                    for try await event in session.uploads.upload(
                        data: document.pdfData,
                        fileName: document.suggestedName,
                        folderName: folder
                    ) {
                        if case .finished(let state) = event, state.isUsable {
                            model.attachments.append(
                                ChatAttachment(
                                    name: UploadService.sanitize(fileName: document.suggestedName),
                                    folderName: folder))
                        } else if case .finished(.failed(let reason)) = event {
                            scanError = reason
                        }
                    }
                } catch {
                    scanError = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - Pieces

private struct MessageBubble: View {
    let message: ChatMessage
    var onSelectCitation: (AnnexureMention) -> Void = { _ in }

    var body: some View {
        if message.role == .user {
            HStack {
                Spacer(minLength: 40)
                Text(message.content)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 16))
            }
        } else {
            AnswerView(
                content: StreamContent.parse(message.content),
                isStreaming: false,
                onSelectCitation: onSelectCitation)
        }
    }
}

private struct AnswerView: View {
    let content: StreamContent
    let isStreaming: Bool
    var onSelectCitation: (AnnexureMention) -> Void = { _ in }
    @State private var openArtifact: StreamArtifact?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !content.prose.isEmpty {
                Text(content.prose)
                    .textSelection(.enabled)
            }

            if !content.mentions.isEmpty {
                CitationStrip(mentions: content.mentions, onSelect: onSelectCitation)
            }

            ForEach(content.artifacts) { artifact in
                Button {
                    openArtifact = artifact
                } label: {
                    ArtifactCard(artifact: artifact)
                }
                .buttonStyle(.plain)
            }

            ForEach(content.errors, id: \.self) { error in
                Notice(icon: "exclamationmark.circle", text: error, tint: .red)
            }

            if content.wasInterrupted {
                Notice(
                    icon: "exclamationmark.triangle",
                    text: "This answer was interrupted before it finished.",
                    tint: .orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(item: $openArtifact) { artifact in
            ArtifactDetailView(artifact: artifact)
        }
    }
}

/// Drafts and chronologies are delivered as separate documents rather than inline prose,
/// so they get their own surface instead of being flattened into the transcript.
private struct ArtifactCard: View {
    let artifact: StreamArtifact

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: artifact.kind == .canvas ? "doc.text" : "tablecells")
                .font(.title3)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(artifact.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Text(artifact.kind == .canvas ? "Document" : "Table")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
    }
}

private struct Notice: View {
    let icon: String
    let text: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
            Text(text)
        }
        .font(.footnote)
        .foregroundStyle(tint)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}
