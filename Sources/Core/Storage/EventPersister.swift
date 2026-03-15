import Foundation

/// Batched write buffer between the main/I/O thread and SQLite.
///
/// Events are buffered in memory (fast, NSLock-protected) and flushed
/// to the EventStore periodically or when the buffer reaches a threshold.
/// All SQLite writes happen on the storage queue, never on the I/O or main thread.
public final class EventPersister {
    private let store: EventStore
    private let lock = NSLock()
    private var eventBuffer: [ActivityEvent] = []
    private var statsBuffer: [(UUID, SessionStatsSnapshot)] = []
    private var timer: DispatchSourceTimer?

    private let flushInterval: TimeInterval
    private let flushThreshold: Int

    /// Create a persister that buffers events and flushes to the store.
    /// - Parameters:
    ///   - store: The EventStore to write to.
    ///   - flushInterval: How often to flush (seconds). Default: 5.
    ///   - flushThreshold: Flush when buffer hits this many events. Default: 100.
    public init(store: EventStore, flushInterval: TimeInterval = 5, flushThreshold: Int = 100) {
        self.store = store
        self.flushInterval = flushInterval
        self.flushThreshold = flushThreshold
        startTimer()
    }

    deinit {
        timer?.cancel()
        flushSync()
    }

    // MARK: - Buffering (called from main thread, must be fast)

    /// Buffer events for later persistence. Sub-microsecond: just a lock + array append.
    public func buffer(events: [ActivityEvent]) {
        guard !events.isEmpty else { return }
        lock.lock()
        eventBuffer.append(contentsOf: events)
        let shouldFlush = eventBuffer.count >= flushThreshold
        lock.unlock()

        if shouldFlush {
            flush()
        }
    }

    /// Buffer a single event.
    public func buffer(event: ActivityEvent) {
        lock.lock()
        eventBuffer.append(event)
        let shouldFlush = eventBuffer.count >= flushThreshold
        lock.unlock()

        if shouldFlush {
            flush()
        }
    }

    /// Buffer a stats snapshot for periodic persistence.
    public func bufferStats(sessionId: UUID, stats: SessionStatsSnapshot) {
        lock.lock()
        // Replace existing entry for this session or add new
        if let idx = statsBuffer.firstIndex(where: { $0.0 == sessionId }) {
            statsBuffer[idx] = (sessionId, stats)
        } else {
            statsBuffer.append((sessionId, stats))
        }
        lock.unlock()
    }

    // MARK: - Flushing

    /// Flush buffered data to SQLite asynchronously on a background queue.
    public func flush() {
        let (events, stats) = drainBuffers()
        guard !events.isEmpty || !stats.isEmpty else { return }

        DispatchQueue.global(qos: .utility).async { [store] in
            if !events.isEmpty {
                try? store.persistEvents(events)
            }
            for (sessionId, snapshot) in stats {
                try? store.updateSessionStats(sessionId: sessionId, stats: snapshot)
            }
        }
    }

    /// Flush synchronously. Call on app termination to ensure all data is written.
    public func flushSync() {
        let (events, stats) = drainBuffers()
        guard !events.isEmpty || !stats.isEmpty else { return }

        if !events.isEmpty {
            try? store.persistEvents(events)
        }
        for (sessionId, snapshot) in stats {
            try? store.updateSessionStats(sessionId: sessionId, stats: snapshot)
        }
    }

    /// Number of buffered events (for diagnostics).
    public var bufferedCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return eventBuffer.count
    }

    // MARK: - Internals

    private func drainBuffers() -> ([ActivityEvent], [(UUID, SessionStatsSnapshot)]) {
        lock.lock()
        let events = eventBuffer
        let stats = statsBuffer
        eventBuffer.removeAll(keepingCapacity: true)
        statsBuffer.removeAll(keepingCapacity: true)
        lock.unlock()
        return (events, stats)
    }

    private func startTimer() {
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + flushInterval, repeating: flushInterval)
        timer.setEventHandler { [weak self] in
            self?.flush()
        }
        timer.resume()
        self.timer = timer
    }
}
