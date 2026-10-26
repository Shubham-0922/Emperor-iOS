import Foundation

/// Cover images for the Library's cards, as the web's `Cover.jsx` and `coverQueue.js` ask for them.
///
/// - A document marked `cover: none`, or one that is not a PDF, never asks: its typographic cover
///   is all there is.
/// - At most six requests are in flight; the rest wait their turn.
/// - "Still rendering" (`cover_pending`) is asked again after 1.5 s and then 4 s, then given up.
/// - "No cover" is remembered for the session, and the images for the last 200 asked, in memory
///   only — the covers are cached by the server for a week anyway.
actor LibraryCoverLoader {
    private let service: any LibraryProviding
    private let retryDelays: [TimeInterval]
    private let capacity: Int
    private let maxInFlight: Int

    private var images: [String: Data] = [:]
    private var order: [String] = []
    private var noCover: Set<Int> = []
    private var inFlight = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var pending: [String: Task<Data?, Never>] = [:]

    init(service: any LibraryProviding, retryDelays: [TimeInterval] = [1.5, 4], capacity: Int = 200, maxInFlight: Int = 6) {
        self.service = service
        self.retryDelays = retryDelays
        self.capacity = capacity
        self.maxInFlight = maxInFlight
    }

    /// The cover image for `doc` at `width`, or `nil` when the typographic cover should stay.
    func image(for doc: LibraryDoc, width: Int) async -> Data? {
        guard doc.coverWanted, !noCover.contains(doc.id) else { return nil }
        let key = "\(doc.id)-\(width)"
        if let hit = images[key] {
            touch(key)
            return hit
        }
        if let running = pending[key] { return await running.value }
        let task = Task { await self.fetch(doc: doc, width: width, key: key) }
        pending[key] = task
        let data = await task.value
        pending[key] = nil
        return data
    }

    /// What is cached for `doc` at `width` right now, without asking.
    func cached(_ doc: LibraryDoc, width: Int) -> Data? { images["\(doc.id)-\(width)"] }

    private func fetch(doc: LibraryDoc, width: Int, key: String) async -> Data? {
        var attempt = 0
        while true {
            await acquire()
            let result = await service.cover(id: doc.id, width: width, web: doc.cover == "web", attempt: attempt)
            release()
            switch result {
            case .image(let data):
                store(data, key)
                return data
            case .none:
                noCover.insert(doc.id)
                return nil
            case .pending:
                guard attempt < retryDelays.count, !Task.isCancelled else { return nil }
                let delay = retryDelays[attempt]
                attempt += 1
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
    }

    private func acquire() async {
        if inFlight < maxInFlight {
            inFlight += 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    private func release() {
        if waiters.isEmpty {
            inFlight -= 1
        } else {
            // The slot passes straight to the next in line.
            waiters.removeFirst().resume()
        }
    }

    private func store(_ data: Data, _ key: String) {
        images[key] = data
        touch(key)
        while order.count > capacity {
            images[order.removeFirst()] = nil
        }
    }

    private func touch(_ key: String) {
        order.removeAll { $0 == key }
        order.append(key)
    }
}
