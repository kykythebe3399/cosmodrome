import Foundation

/// Compares agent efficiency across task types using historical data.
/// Query-only — reads from task_records joined with sessions.
public final class EfficiencyTracker {
    private let store: EventStore

    public init(store: EventStore) {
        self.store = store
    }

    /// Efficiency stats for a (agent_type, classification) pair.
    public struct EfficiencyEntry {
        public let agentType: String
        public let classification: String
        public let medianCost: Double
        public let medianDuration: TimeInterval
        public let taskCount: Int
    }

    /// Get efficiency comparison across agent types.
    public func compare(classification: TaskClassification? = nil) -> [EfficiencyEntry] {
        // Load all completed sessions with their task records
        guard let sessions = try? store.loadSessionHistory(limit: 500) else { return [] }

        // Group sessions by agent type
        var tasksByAgent: [String: [(cost: Double, duration: TimeInterval, classification: String)]] = [:]

        for session in sessions {
            guard let agentType = session.agentType else { continue }

            guard let tasks = try? store.loadTaskRecords(
                sessionId: UUID(uuidString: session.id),
                classification: classification?.rawValue,
                limit: 200
            ) else { continue }

            for task in tasks where task.cost != nil && task.duration != nil {
                tasksByAgent[agentType, default: []].append((
                    cost: task.cost!,
                    duration: task.duration!,
                    classification: task.classification ?? "unknown"
                ))
            }
        }

        var results: [EfficiencyEntry] = []

        for (agentType, tasks) in tasksByAgent {
            // Group by classification
            let byClassification = Dictionary(grouping: tasks) { $0.classification }

            for (cls, classTasks) in byClassification {
                guard classTasks.count >= 3 else { continue }

                let costs = classTasks.map(\.cost).sorted()
                let durations = classTasks.map(\.duration).sorted()

                results.append(EfficiencyEntry(
                    agentType: agentType,
                    classification: cls,
                    medianCost: costs[costs.count / 2],
                    medianDuration: durations[durations.count / 2],
                    taskCount: classTasks.count
                ))
            }
        }

        return results.sorted { a, b in
            if a.classification != b.classification { return a.classification < b.classification }
            return a.medianCost < b.medianCost
        }
    }

    /// Get efficiency summary for a specific agent type.
    public func summary(agentType: String) -> (totalCost: Double, totalTasks: Int, avgCostPerTask: Double)? {
        guard let sessions = try? store.loadSessionHistory(limit: 500) else { return nil }

        let agentSessions = sessions.filter { $0.agentType == agentType }
        guard !agentSessions.isEmpty else { return nil }

        let totalCost = agentSessions.reduce(0.0) { $0 + $1.totalCost }
        let totalTasks = agentSessions.reduce(0) { $0 + $1.totalTasks }
        let avgCost = totalTasks > 0 ? totalCost / Double(totalTasks) : 0

        return (totalCost: totalCost, totalTasks: totalTasks, avgCostPerTask: avgCost)
    }
}
