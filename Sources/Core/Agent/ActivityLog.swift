import Foundation

/// A single event captured from agent output.
public struct ActivityEvent {
    public let timestamp: Date
    public let sessionId: UUID
    public let sessionName: String
    public let kind: EventKind

    public enum EventKind {
        case taskStarted
        case taskCompleted(duration: TimeInterval)
        case fileRead(path: String)
        case fileWrite(path: String, added: Int?, removed: Int?)
        case commandRun(command: String)
        case error(message: String)
        case modelChanged(model: String)
        case stateChanged(from: AgentState, to: AgentState)
        case subagentStarted(name: String, description: String)
        case subagentCompleted(name: String, duration: TimeInterval)
        case commandCompleted(command: String?, exitCode: Int?, duration: TimeInterval)
    }

    public init(timestamp: Date, sessionId: UUID, sessionName: String, kind: EventKind) {
        self.timestamp = timestamp
        self.sessionId = sessionId
        self.sessionName = sessionName
        self.kind = kind
    }
}

/// Per-project activity log. Append-only, in-memory, bounded.
/// Thread-safe: events are appended from the I/O thread, read from the main thread.
public final class ActivityLog {
    private var _events: [ActivityEvent] = []
    private let lock = NSLock()
    private let maxEvents = 10_000

    public init() {}

    /// Append an event. Called from I/O thread, must be fast.
    public func append(_ event: ActivityEvent) {
        lock.lock()
        _events.append(event)
        if _events.count > maxEvents {
            _events.removeFirst(_events.count - maxEvents)
        }
        lock.unlock()
    }

    /// Append multiple events at once.
    public func append(contentsOf events: [ActivityEvent]) {
        guard !events.isEmpty else { return }
        lock.lock()
        _events.append(contentsOf: events)
        if _events.count > maxEvents {
            _events.removeFirst(_events.count - maxEvents)
        }
        lock.unlock()
    }

    /// Snapshot of all events. Safe from any thread.
    public var events: [ActivityEvent] {
        lock.lock()
        defer { lock.unlock() }
        return _events
    }

    /// Events for a specific session.
    public func events(for sessionId: UUID) -> [ActivityEvent] {
        events.filter { $0.sessionId == sessionId }
    }

    /// Files written across all sessions in this project.
    public var filesChanged: [String] {
        events.compactMap {
            if case .fileWrite(let path, _, _) = $0.kind { return path }
            return nil
        }
    }

    /// Events from the last N minutes.
    public func summary(last minutes: Int) -> [ActivityEvent] {
        let cutoff = Date().addingTimeInterval(-Double(minutes) * 60)
        return events.filter { $0.timestamp > cutoff }
    }

    /// Total event count.
    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return _events.count
    }

    // MARK: - Query Methods

    /// Group events by session ID.
    public func eventsBySession() -> [UUID: [ActivityEvent]] {
        Dictionary(grouping: events, by: \.sessionId)
    }

    /// Summary of activity since a given date.
    public func summary(since: Date) -> ActivitySummary {
        let recentEvents = events.filter { $0.timestamp > since }
        var tasksCompleted = 0
        var filesChanged = Set<String>()
        var errors = 0
        var sessionIds = Set<UUID>()
        for event in recentEvents {
            sessionIds.insert(event.sessionId)
            switch event.kind {
            case .taskCompleted:
                tasksCompleted += 1
            case .fileWrite(let path, _, _):
                filesChanged.insert(path)
            case .error:
                errors += 1
            default:
                break
            }
        }

        return ActivitySummary(
            tasksCompleted: tasksCompleted,
            filesChanged: filesChanged.count,
            errors: errors,
            activeSessions: sessionIds.count,
            eventCount: recentEvents.count
        )
    }

    /// Files changed, grouped by session.
    public func filesChangedBySession() -> [UUID: [String]] {
        var result: [UUID: [String]] = [:]
        for event in events {
            if case .fileWrite(let path, _, _) = event.kind {
                result[event.sessionId, default: []].append(path)
            }
        }
        return result
    }

    /// Most recent event timestamp per session (for sorting sessions by activity).
    public func lastActivityBySession() -> [UUID: Date] {
        var result: [UUID: Date] = [:]
        for event in events {
            if let existing = result[event.sessionId] {
                if event.timestamp > existing {
                    result[event.sessionId] = event.timestamp
                }
            } else {
                result[event.sessionId] = event.timestamp
            }
        }
        return result
    }

    /// Session name for a given session ID (from most recent event).
    public func sessionName(for sessionId: UUID) -> String? {
        events.last(where: { $0.sessionId == sessionId })?.sessionName
    }

    /// Export all events as JSON-serializable dictionaries.
    public func exportJSON() -> [[String: Any]] {
        let formatter = ISO8601DateFormatter()
        return events.map { event in
            var dict: [String: Any] = [
                "timestamp": formatter.string(from: event.timestamp),
                "sessionId": event.sessionId.uuidString,
                "sessionName": event.sessionName,
                "kind": event.kind.label,
            ]
            switch event.kind {
            case .fileRead(let path):
                dict["path"] = path
            case .fileWrite(let path, let added, let removed):
                dict["path"] = path
                if let a = added { dict["added"] = a }
                if let r = removed { dict["removed"] = r }
            case .commandRun(let cmd):
                dict["command"] = cmd
            case .commandCompleted(let cmd, let exit, let dur):
                if let c = cmd { dict["command"] = c }
                if let e = exit { dict["exitCode"] = e }
                dict["duration"] = dur
            case .error(let msg):
                dict["message"] = msg
            case .modelChanged(let model):
                dict["model"] = model
            case .taskCompleted(let dur):
                dict["duration"] = dur
            case .subagentStarted(let name, let desc):
                dict["name"] = name
                dict["description"] = desc
            case .subagentCompleted(let name, let dur):
                dict["name"] = name
                dict["duration"] = dur
            case .stateChanged(let from, let to):
                dict["from"] = from.rawValue
                dict["to"] = to.rawValue
            case .taskStarted:
                break
            }
            return dict
        }
    }
}

/// Summary of activity over a time window.
public struct ActivitySummary {
    public let tasksCompleted: Int
    public let filesChanged: Int
    public let errors: Int
    public let activeSessions: Int
    public let eventCount: Int

    public init(tasksCompleted: Int, filesChanged: Int, errors: Int, activeSessions: Int, eventCount: Int) {
        self.tasksCompleted = tasksCompleted
        self.filesChanged = filesChanged
        self.errors = errors
        self.activeSessions = activeSessions
        self.eventCount = eventCount
    }
}

// MARK: - EventKind helpers

extension ActivityEvent.EventKind {
    /// Human-readable label for the event kind.
    public var label: String {
        switch self {
        case .taskStarted: return "taskStarted"
        case .taskCompleted: return "taskCompleted"
        case .fileRead: return "fileRead"
        case .fileWrite: return "fileWrite"
        case .commandRun: return "commandRun"
        case .commandCompleted: return "commandCompleted"
        case .error: return "error"
        case .modelChanged: return "modelChanged"
        case .stateChanged: return "stateChanged"
        case .subagentStarted: return "subagentStarted"
        case .subagentCompleted: return "subagentCompleted"
        }
    }

    /// Category for filtering.
    public var category: EventCategory {
        switch self {
        case .fileRead, .fileWrite: return .files
        case .commandRun, .commandCompleted: return .commands
        case .error: return .errors
        case .taskStarted, .taskCompleted: return .tasks
        case .subagentStarted, .subagentCompleted: return .subagents
        case .stateChanged, .modelChanged: return .state
        }
    }
}

/// Categories for filtering events in the UI.
public enum EventCategory: String, CaseIterable {
    case files, commands, errors, tasks, subagents, state
}
