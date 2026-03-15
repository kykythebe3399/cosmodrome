import Foundation

/// Mines workflow patterns from historical event sequences.
/// Detects bigrams like "after editing src/auth, you run tests 85% of the time."
public final class WorkflowMiner {
    private let store: EventStore
    /// Minimum observation count before surfacing a suggestion.
    private let minCount: Int
    /// Minimum probability to surface a suggestion.
    private let minProbability: Double

    public init(store: EventStore, minCount: Int = 5, minProbability: Double = 0.7) {
        self.store = store
        self.minCount = minCount
        self.minProbability = minProbability
    }

    /// A learned workflow suggestion.
    public struct Suggestion {
        public let action: String
        public let context: String
        public let probability: Double
        public let observationCount: Int

        /// Human-readable label, e.g. "Run tests (you do this 85% of the time after editing auth/)"
        public var label: String {
            let pct = Int(probability * 100)
            return "\(action) (you do this \(pct)% of the time \(context))"
        }
    }

    /// Get workflow suggestions based on what just happened.
    public func suggest(afterEvent event: ActivityEvent,
                        projectPath: String? = nil) -> [Suggestion] {
        let (triggerKind, triggerContext) = extractTrigger(from: event)
        guard let triggerKind else { return [] }

        guard let raw = try? store.lookupWorkflowSuggestions(
            projectPath: projectPath,
            triggerKind: triggerKind,
            triggerContext: triggerContext,
            minCount: minCount
        ) else { return [] }

        return raw
            .filter { $0.probability >= minProbability }
            .prefix(3)
            .map { suggestion in
                Suggestion(
                    action: describeAction(kind: suggestion.followKind, context: suggestion.followContext),
                    context: describeContext(kind: triggerKind, context: triggerContext),
                    probability: suggestion.probability,
                    observationCount: suggestion.count
                )
            }
    }

    /// Record a sequence observation: event A was followed by event B within the time window.
    public func recordSequence(trigger: ActivityEvent, follow: ActivityEvent,
                               projectPath: String?) {
        let (triggerKind, triggerContext) = extractTrigger(from: trigger)
        let (followKind, followContext) = extractTrigger(from: follow)
        guard let triggerKind, let followKind else { return }

        try? store.recordWorkflowSequence(
            projectPath: projectPath,
            triggerKind: triggerKind,
            triggerContext: triggerContext,
            followKind: followKind,
            followContext: followContext
        )
    }

    /// Record that a trigger event occurred (for computing probabilities).
    public func recordTrigger(event: ActivityEvent, projectPath: String?) {
        let (triggerKind, triggerContext) = extractTrigger(from: event)
        guard let triggerKind else { return }

        try? store.incrementTriggerCount(
            projectPath: projectPath,
            triggerKind: triggerKind,
            triggerContext: triggerContext
        )
    }

    // MARK: - Internals

    private func extractTrigger(from event: ActivityEvent) -> (kind: String?, context: String?) {
        switch event.kind {
        case .fileWrite(let path, _, _):
            let dir = (path as NSString).deletingLastPathComponent
            let context = (dir as NSString).lastPathComponent
            return ("fileWrite", context.isEmpty ? nil : context)
        case .commandRun(let cmd):
            let firstWord = cmd.split(separator: " ").first.map(String.init)
            return ("commandRun", firstWord)
        case .commandCompleted(let cmd, _, _):
            let firstWord = cmd?.split(separator: " ").first.map(String.init)
            return ("commandCompleted", firstWord)
        case .taskCompleted:
            return ("taskCompleted", nil)
        case .error:
            return ("error", nil)
        default:
            return (nil, nil)
        }
    }

    private func describeAction(kind: String, context: String?) -> String {
        switch kind {
        case "commandRun":
            return context.map { "Run \($0)" } ?? "Run command"
        case "fileWrite":
            return context.map { "Edit \($0)/" } ?? "Edit files"
        case "taskCompleted":
            return "Complete task"
        default:
            return context ?? kind
        }
    }

    private func describeContext(kind: String, context: String?) -> String {
        switch kind {
        case "fileWrite":
            return context.map { "after editing \($0)/" } ?? "after file edits"
        case "commandRun", "commandCompleted":
            return context.map { "after running \($0)" } ?? "after commands"
        case "taskCompleted":
            return "after task completion"
        case "error":
            return "after errors"
        default:
            return "after \(kind)"
        }
    }
}
