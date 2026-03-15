import Foundation

/// Predicts task cost based on historical task records.
/// Uses classification and file count to find similar past tasks.
public final class CostPredictor {
    private let store: EventStore

    public init(store: EventStore) {
        self.store = store
    }

    /// Cost prediction for an upcoming or in-progress task.
    public struct Prediction {
        public let median: Double
        public let p75: Double
        public let sampleSize: Int
        public let classification: String

        /// Formatted range string, e.g. "$2-4"
        public var rangeString: String {
            if median < 0.01 && p75 < 0.01 { return "" }
            let lo = SessionStats.formatCost(median)
            let hi = SessionStats.formatCost(p75)
            if lo == hi { return "~\(lo)" }
            return "\(lo)-\(hi)"
        }
    }

    /// Predict cost for a task based on classification and expected file count.
    public func predict(classification: TaskClassification,
                        projectPath: String? = nil,
                        expectedFileCount: Int? = nil) -> Prediction? {
        guard classification != .unknown else { return nil }

        // Query historical tasks with same classification
        guard let tasks = try? store.loadTaskRecords(
            classification: classification.rawValue,
            limit: 200
        ) else { return nil }

        // Filter to tasks that have cost data
        var costs = tasks.compactMap { $0.cost }.filter { $0 > 0 }

        // If we have file count, filter to similar range (within 2x)
        if let expected = expectedFileCount, expected > 0 {
            let similarTasks = tasks.filter { task in
                task.cost != nil && task.cost! > 0 &&
                task.filesChanged > 0 &&
                task.filesChanged >= expected / 2 &&
                task.filesChanged <= expected * 2
            }
            let similarCosts = similarTasks.compactMap { $0.cost }
            if similarCosts.count >= 3 {
                costs = similarCosts
            }
        }

        guard costs.count >= 3 else { return nil }

        costs.sort()
        let median = costs[costs.count / 2]
        let p75Index = costs.count * 3 / 4
        let p75 = costs[min(p75Index, costs.count - 1)]

        return Prediction(
            median: median,
            p75: p75,
            sampleSize: costs.count,
            classification: classification.rawValue
        )
    }

    /// Predict cost for a task based on the events seen so far.
    public func predictFromEvents(_ events: [ActivityEvent],
                                  projectPath: String? = nil) -> Prediction? {
        let classification = TaskClassifier.classify(events: events)
        let fileCount = Set(events.compactMap { event -> String? in
            if case .fileWrite(let path, _, _) = event.kind { return path }
            return nil
        }).count

        return predict(
            classification: classification,
            projectPath: projectPath,
            expectedFileCount: fileCount > 0 ? fileCount : nil
        )
    }
}
