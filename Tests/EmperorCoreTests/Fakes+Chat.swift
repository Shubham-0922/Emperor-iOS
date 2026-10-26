import Foundation
@testable import EmperorCore

// Moved out of `Fakes.swift` unchanged; each area's stand-ins live in a file of their own.

final class FakeChatList: ChatListProviding, @unchecked Sendable {
    var chats: [ChatSummary] = []
    var error: Error?

    func chats() async throws -> [ChatSummary] {
        if let error { throw error }
        return chats
    }
}

/// A `ChatProviding` that does nothing. The citation and scan tests drive `ChatViewModel`
/// without running a turn, so the chat service only has to exist.
final class InertChat: ChatProviding, @unchecked Sendable {
    func messages(chatID: String) async throws -> [ChatMessage] { [] }
    func streamStatus(chatID: String) async throws -> StreamStatus { StreamStatus(active: false) }
    func send(
        history: [ChatMessage], chatID: String, model: ChatModel, role: ChatRole?,
        attachments: [ChatAttachment]?, webSearch: Bool
    ) async throws -> AsyncThrowingStream<ChatTurnEvent, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}

/// A `ChatProviding` whose answers come from scripts, for following a run, stopping one, and
/// adopting what the server saved. Each script is consumed in order and its last entry repeats.
final class ScriptedChat: ChatProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var _statuses: [Result<StreamStatus, Error>] = [.success(StreamStatus(active: false))]
    private var _histories: [Result<[ChatMessage], Error>] = [.success([])]
    private var _statusCalls = 0
    private var _messagesCalls = 0
    private var _stopCalls = 0
    private var _sent: [[ChatMessage]] = []

    var events: [ChatTurnEvent] = []
    /// `nil` answers as a server that could not be reached.
    var stopReply: StopReply? = StopReply(
        success: true, running: true, stopped: true, savedBy: "run", error: nil)

    var statusCalls: Int { lock.withLock { _statusCalls } }
    var messagesCalls: Int { lock.withLock { _messagesCalls } }
    var stopCalls: Int { lock.withLock { _stopCalls } }
    var sent: [[ChatMessage]] { lock.withLock { _sent } }

    func scriptStatuses(_ statuses: [Result<StreamStatus, Error>]) {
        lock.withLock { _statuses = statuses }
    }

    func scriptStatuses(_ statuses: [StreamStatus]) {
        scriptStatuses(statuses.map { .success($0) })
    }

    func scriptHistories(_ histories: [[ChatMessage]]) {
        lock.withLock { _histories = histories.map { .success($0) } }
    }

    func scriptHistories(_ histories: [Result<[ChatMessage], Error>]) {
        lock.withLock { _histories = histories }
    }

    private static func next<T>(_ script: inout [T]) -> T {
        script.count > 1 ? script.removeFirst() : script[0]
    }

    func messages(chatID: String) async throws -> [ChatMessage] {
        let result = lock.withLock { () -> Result<[ChatMessage], Error> in
            _messagesCalls += 1
            return Self.next(&_histories)
        }
        return try result.get()
    }

    func streamStatus(chatID: String) async throws -> StreamStatus {
        let result = lock.withLock { () -> Result<StreamStatus, Error> in
            _statusCalls += 1
            return Self.next(&_statuses)
        }
        return try result.get()
    }

    func stopRun(chatID: String) async throws -> StopReply {
        lock.withLock { _stopCalls += 1 }
        guard let stopReply else { throw APIError.transport("The network connection was lost.") }
        return stopReply
    }

    func send(
        history: [ChatMessage], chatID: String, model: ChatModel, role: ChatRole?,
        attachments: [ChatAttachment]?, webSearch: Bool
    ) async throws -> AsyncThrowingStream<ChatTurnEvent, Error> {
        lock.withLock { _sent.append(history) }
        let queued = events
        return AsyncThrowingStream { continuation in
            for event in queued { continuation.yield(event) }
            continuation.finish()
        }
    }
}

/// A clock that moves only when the follower waits, by exactly what it waited, and remembers
/// every wait — so back-off and the 35-minute limit can be tested in no time at all.
final class SteppedClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 1_800_000_000)
    private var _waits: [Int] = []

    var waits: [Int] { lock.withLock { _waits } }

    var timing: FollowTiming {
        FollowTiming(
            now: { [self] in lock.withLock { current } },
            sleep: { [self] ms in
                lock.withLock {
                    _waits.append(ms)
                    current = current.addingTimeInterval(Double(ms) / 1000)
                }
                await Task.yield()
            })
    }
}
