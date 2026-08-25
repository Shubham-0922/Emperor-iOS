import Foundation
#if canImport(Darwin)
import Observation
#endif

/// Turn state for one conversation.
///
/// `@Observable` is applied on Apple platforms only. The Linux toolchain ships a
/// `libswiftObservation.so` with an undefined symbol (`swift::threading::fatal`), so applying
/// the macro there compiles but fails to *link* — which would take the whole test suite with
/// it. SwiftUI observation is an Apple concern anyway; on Linux this is a plain class, which
/// is exactly what the tests need.
#if canImport(Darwin)
@Observable
#endif
@MainActor
final class ChatViewModel {
    /// Finished turns, oldest first.
    private(set) var messages: [ChatMessage] = []
    /// The answer currently streaming, if any.
    private(set) var live: StreamContent?
    /// Transient progress ("Reading: sale_deed.pdf"). Not part of the transcript.
    private(set) var status: String?
    /// Shown when the server refuses a concurrent run — deliberately outside the transcript.
    private(set) var busyNotice: String?
    /// Plan and work log for the turn currently streaming.
    private(set) var progress = ReasoningSnapshot()
    private(set) var isStreaming = false
    private(set) var isLoading = false
    var errorMessage: String?

    /// Set when a run finished but the server says the answer was cut short.
    private(set) var wasInterrupted = false

    let chatID: String
    var attachments: [ChatAttachment] = []
    var model: ChatModel = .default
    var role: ChatRole = .default

    private let service: any ChatProviding
    private var streamTask: Task<Void, Never>?

    init(chatID: String, service: any ChatProviding) {
        self.chatID = chatID
        self.service = service
    }

    static func newChatID() -> String { UUID().uuidString }

    // MARK: - Loading

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            messages = try await service.messages(chatID: chatID)
            // A run may have continued server-side while the app was closed — generation is
            // not tied to the socket.
            await recoverInFlightRun()
        } catch let error as APIError {
            // A brand-new chat has no row yet, which this API reports as an error rather than
            // an empty list. That is not a failure worth showing.
            if case .server(_, let message) = error, message.contains("Chat not found") { return }
            errorMessage = error.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Rejoins a generation still running on the server.
    private func recoverInFlightRun() async {
        guard let status = try? await service.streamStatus(chatID: chatID), status.error == nil
        else { return }

        if status.active, let content = status.content, !content.isEmpty {
            live = StreamContent.parse(content)
            isStreaming = true
            pollUntilFinished()
        } else if status.incomplete == true {
            wasInterrupted = true
        }
    }

    /// Polls a rejoined run to completion.
    ///
    /// There is no way to re-attach to the byte stream of a run started by another
    /// connection, so recovery is polling `/stream-status`, whose `content` is always the
    /// full draft rather than a delta.
    private func pollUntilFinished() {
        streamTask?.cancel()
        streamTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let status = try? await self.service.streamStatus(chatID: self.chatID)
                else { continue }

                if let content = status.content, !content.isEmpty {
                    self.live = StreamContent.parse(content)
                }
                if !status.active {
                    self.wasInterrupted = status.incomplete == true
                    await self.finishStreaming()
                    return
                }
            }
        }
    }

    // MARK: - Sending

    func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isStreaming else { return }

        busyNotice = nil
        wasInterrupted = false
        errorMessage = nil
        progress = ReasoningSnapshot()
        var turn = ChatMessage(role: .user, content: trimmed, id: UUID().uuidString)
        // Also on the message, not just the top-level array — the scanned-document check
        // reads it from here, and later turns rely on it to keep files in scope.
        if !attachments.isEmpty {
            turn.attachments = attachments.map(\.jsonValue)
        }
        messages.append(turn)
        isStreaming = true
        live = StreamContent()
        status = "Preparing…"

        let outbound = attachments.isEmpty ? nil : attachments
        streamTask = Task { [weak self] in
            guard let self else { return }
            do {
                // The full conversation must go every time: the server replaces the chat's
                // stored messages with exactly what it receives, so omitting history deletes it.
                let stream = try await self.service.send(
                    history: self.messages,
                    chatID: self.chatID,
                    model: self.model,
                    role: self.role,
                    attachments: outbound,
                    // Web search is not exposed in the UI yet. The server also auto-triggers
                    // it on keywords in the message, so false is "don't ask for it", not
                    // "never search".
                    webSearch: false)

                for try await event in stream {
                    switch event {
                    case .status(let text):
                        self.status = text
                    case .busy(let notice):
                        self.busyNotice = notice
                        // Nothing was lost and nothing was started — drop the optimistic
                        // user bubble back into the composer's place rather than implying
                        // a turn is running.
                        self.live = nil
                    case .content(let content):
                        self.live = content
                    case .progress(let snapshot):
                        self.progress = snapshot
                    case .usage:
                        break
                    }
                }
                await self.confirmCompletion()
            } catch is CancellationError {
                await self.finishStreaming()
            } catch {
                self.errorMessage = (error as? APIError)?.errorDescription
                    ?? error.localizedDescription
                await self.finishStreaming()
            }
        }
    }

    /// Confirms the answer actually finished.
    ///
    /// An aborted run ends its response cleanly with no error bytes, so end-of-stream alone
    /// proves nothing. `/stream-status` is the only authoritative signal.
    private func confirmCompletion() async {
        if let status = try? await service.streamStatus(chatID: chatID), status.error == nil {
            wasInterrupted = status.incomplete == true
        }
        await finishStreaming()
    }

    private func finishStreaming() async {
        if let live, !live.prose.isEmpty || !live.artifacts.isEmpty {
            // The server has already persisted this turn — both before and after generation —
            // so there is nothing to sync back. Calling /sync here would be actively harmful:
            // it silently drops any chat whose message count is lower than the server's.
            messages.append(ChatMessage(role: .assistant, content: live.prose))
        }
        live = nil
        status = nil
        isStreaming = false
        streamTask = nil
    }

    /// Stops rendering locally. It does **not** stop the run: generation continues on the
    /// server and will be there on the next load.
    func stop() {
        streamTask?.cancel()
        streamTask = nil
        Task { await finishStreaming() }
    }
}
