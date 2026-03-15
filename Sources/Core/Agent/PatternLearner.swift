import Foundation

/// Learns from historical error patterns to predict stuck loops proactively.
/// Uses the EventStore to track which error patterns historically lead to stuck detection.
public final class PatternLearner {
    private let store: EventStore
    /// Threshold above which we predict stuck proactively.
    public let stuckThreshold: Double

    public init(store: EventStore, stuckThreshold: Double = 0.6) {
        self.store = store
        self.stuckThreshold = stuckThreshold
    }

    /// Prediction result for an error pattern.
    public struct Prediction {
        public let patternHash: String
        public let patternText: String
        public let stuckProbability: Double
        public let occurrences: Int
        public let avgResolutionTime: TimeInterval?
        /// True if stuckProbability exceeds the threshold.
        public var isHighRisk: Bool { stuckProbability >= 0.6 }
    }

    /// Predict whether a given error message is likely to lead to a stuck loop,
    /// based on historical data.
    public func predict(errorMessage: String) -> Prediction? {
        let hash = Self.normalizeError(errorMessage)
        guard !hash.isEmpty else { return nil }

        guard let record = try? store.lookupErrorPattern(hash: hash) else {
            return nil
        }

        // Require at least 3 observations for meaningful prediction
        guard record.occurrences >= 3 else { return nil }

        return Prediction(
            patternHash: record.hash,
            patternText: record.text,
            stuckProbability: record.stuckProbability,
            occurrences: record.occurrences,
            avgResolutionTime: record.avgResolutionTime
        )
    }

    /// Record that an error pattern was observed and whether it led to stuck.
    public func recordOutcome(errorMessage: String, ledToStuck: Bool,
                              resolutionTime: TimeInterval? = nil) {
        let hash = Self.normalizeError(errorMessage)
        let text = String(errorMessage.prefix(200))
        guard !hash.isEmpty else { return }

        try? store.recordErrorPattern(
            hash: hash,
            text: text,
            ledToStuck: ledToStuck,
            resolutionTime: resolutionTime
        )
    }

    // MARK: - Normalization

    /// Normalize an error message to a hash key for pattern matching.
    /// Takes first 3 words after lowercasing and stripping file paths and line numbers.
    public static func normalizeError(_ message: String) -> String {
        var cleaned = message.lowercased()

        // Strip file paths (anything like /foo/bar/baz.ext or ./foo/bar)
        cleaned = cleaned.replacingOccurrences(
            of: #"[/\.][\w\-/]+\.\w+"#,
            with: "",
            options: .regularExpression
        )

        // Strip line/column numbers
        cleaned = cleaned.replacingOccurrences(
            of: #"(?:line |l)\d+(?::\d+)?"#,
            with: "",
            options: .regularExpression
        )

        // Strip quoted strings
        cleaned = cleaned.replacingOccurrences(
            of: #"['\"][^'\"]*['\"]"#,
            with: "",
            options: .regularExpression
        )

        // Take first 3 meaningful words
        let words = cleaned
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { $0.count >= 2 }
            .prefix(3)

        return words.joined(separator: " ")
    }
}
