import Foundation

/// Scores session urgency based on state, timing, and stuck detection.
/// Used by fleet overview and session thumbnails to prioritize attention.
public enum UrgencyScorer {

    /// Urgency level, ordered from most to least urgent.
    public enum Level: String, Comparable {
        case critical
        case high
        case medium
        case low
        case none

        private var sortOrder: Int {
            switch self {
            case .critical: return 4
            case .high: return 3
            case .medium: return 2
            case .low: return 1
            case .none: return 0
            }
        }

        public static func < (lhs: Level, rhs: Level) -> Bool {
            lhs.sortOrder < rhs.sortOrder
        }
    }

    /// Computed urgency for a session at a point in time.
    public struct Urgency {
        /// Numeric score for sorting (0–100, higher = more urgent).
        public let value: Int
        /// Categorical level for UI styling.
        public let level: Level
        /// Human-readable reason for the urgency.
        public let reason: String

        public init(value: Int, level: Level, reason: String) {
            self.value = value
            self.level = level
            self.reason = reason
        }
    }

    /// Score the urgency of a session based on its current state and context.
    public static func score(
        state: AgentState,
        stuckInfo: StuckDetector.StuckInfo?,
        stateEnteredAt: Date?,
        needsAttention: Bool
    ) -> Urgency {
        // Stuck sessions are always critical or high
        if let stuck = stuckInfo {
            if stuck.predictedFromHistory {
                return Urgency(value: 75, level: .high, reason: "Likely stuck: \(stuck.pattern ?? "pattern match") (historical)")
            }
            if stuck.retryCount >= 5 || stuck.duration > 300 {
                return Urgency(value: 100, level: .critical, reason: "Stuck: \(stuck.pattern ?? "error loop") (\(stuck.retryCount)x)")
            }
            return Urgency(value: 80, level: .high, reason: "Stuck: \(stuck.pattern ?? "retrying") (\(stuck.retryCount)x)")
        }

        switch state {
        case .error:
            return Urgency(value: 90, level: .critical, reason: "Error state")
        case .needsInput:
            let waitTime = stateEnteredAt.map { Date().timeIntervalSince($0) } ?? 0
            if waitTime > 300 {
                return Urgency(value: 85, level: .critical, reason: "Waiting \(SessionStats.formatDuration(waitTime))")
            } else if waitTime > 60 {
                return Urgency(value: 70, level: .high, reason: "Waiting \(SessionStats.formatDuration(waitTime))")
            }
            return Urgency(value: 50, level: .medium, reason: "Needs input")
        case .working:
            return Urgency(value: 10, level: .low, reason: "Working")
        case .inactive:
            return Urgency(value: 0, level: .none, reason: "Idle")
        }
    }
}
