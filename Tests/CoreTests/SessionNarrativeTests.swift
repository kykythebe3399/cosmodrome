import XCTest
@testable import Core

final class SessionNarrativeTests: XCTestCase {

    private let testSessionId = UUID()

    private func makeEvent(_ kind: ActivityEvent.EventKind, ago: TimeInterval = 0) -> ActivityEvent {
        ActivityEvent(
            timestamp: Date().addingTimeInterval(-ago),
            sessionId: testSessionId,
            sessionName: "test",
            kind: kind
        )
    }

    private func makeStats() -> SessionStats {
        SessionStats()
    }

    // MARK: - Working State

    func testWorkingWithNoEvents() {
        let summary = SessionNarrative.summarize(
            state: .working,
            events: [],
            stats: makeStats(),
            taskStartedAt: Date().addingTimeInterval(-30),
            stuckInfo: nil
        )
        XCTAssert(summary.headline.contains("Working"), "Should contain 'Working'")
        XCTAssertFalse(summary.needsAttention)
    }

    func testWorkingWithFileWrites() {
        let events = [
            makeEvent(.taskStarted, ago: 60),
            makeEvent(.fileWrite(path: "src/auth.ts", added: 10, removed: 5), ago: 30),
            makeEvent(.fileWrite(path: "src/auth.test.ts", added: 20, removed: 0), ago: 20),
        ]
        let summary = SessionNarrative.summarize(
            state: .working,
            events: events,
            stats: makeStats(),
            taskStartedAt: Date().addingTimeInterval(-60),
            stuckInfo: nil
        )
        XCTAssert(summary.headline.contains("2 files") || summary.headline.contains("Editing"),
                  "Should mention files: \(summary.headline)")
    }

    func testWorkingWithCommand() {
        let events = [
            makeEvent(.taskStarted, ago: 30),
            makeEvent(.commandRun(command: "npm test"), ago: 5),
        ]
        let summary = SessionNarrative.summarize(
            state: .working,
            events: events,
            stats: makeStats(),
            taskStartedAt: Date().addingTimeInterval(-30),
            stuckInfo: nil
        )
        XCTAssert(summary.headline.contains("npm test") || summary.headline.contains("Running"),
                  "Should mention command: \(summary.headline)")
    }

    func testWorkingWithSubagent() {
        let events = [
            makeEvent(.taskStarted, ago: 30),
            makeEvent(.subagentStarted(name: "review-code", description: "Reviewing auth changes"), ago: 5),
        ]
        let summary = SessionNarrative.summarize(
            state: .working,
            events: events,
            stats: makeStats(),
            taskStartedAt: Date().addingTimeInterval(-30),
            stuckInfo: nil
        )
        XCTAssert(summary.headline.contains("agent") || summary.headline.contains("review"),
                  "Should mention subagent: \(summary.headline)")
    }

    // MARK: - Needs Input

    func testNeedsInputGeneric() {
        let summary = SessionNarrative.summarize(
            state: .needsInput,
            events: [],
            stats: makeStats(),
            taskStartedAt: nil,
            stuckInfo: nil
        )
        XCTAssert(summary.headline.contains("Waiting"), "Should mention waiting: \(summary.headline)")
        XCTAssertTrue(summary.needsAttention)
    }

    func testNeedsInputWithContext() {
        let summary = SessionNarrative.summarize(
            state: .needsInput,
            events: [],
            stats: makeStats(),
            taskStartedAt: nil,
            stuckInfo: nil,
            promptContext: "delete test fixtures"
        )
        XCTAssert(summary.headline.contains("delete test fixtures"),
                  "Should include prompt context: \(summary.headline)")
    }

    // MARK: - Error State

    func testErrorWithMessage() {
        let events = [
            makeEvent(.error(message: "permission denied"), ago: 5),
        ]
        let summary = SessionNarrative.summarize(
            state: .error,
            events: events,
            stats: makeStats(),
            taskStartedAt: nil,
            stuckInfo: nil
        )
        XCTAssert(summary.headline.contains("permission denied"),
                  "Should include error message: \(summary.headline)")
        XCTAssertTrue(summary.needsAttention)
    }

    // MARK: - Inactive State

    func testInactiveAfterCompletion() {
        let events = [
            makeEvent(.taskStarted, ago: 300),
            makeEvent(.fileWrite(path: "src/auth.ts", added: 10, removed: 5), ago: 120),
            makeEvent(.taskCompleted(duration: 300), ago: 10),
        ]
        let stats = makeStats()
        stats.recordCost(4.20)
        let summary = SessionNarrative.summarize(
            state: .inactive,
            events: events,
            stats: stats,
            taskStartedAt: nil,
            stuckInfo: nil
        )
        XCTAssert(summary.headline.contains("Done"), "Should say done: \(summary.headline)")
        XCTAssert(summary.headline.contains("$4.20") || summary.headline.contains("5m"),
                  "Should include stats: \(summary.headline)")
    }

    func testInactiveNoActivity() {
        let summary = SessionNarrative.summarize(
            state: .inactive,
            events: [],
            stats: makeStats(),
            taskStartedAt: nil,
            stuckInfo: nil
        )
        XCTAssertEqual(summary.headline, "Ready")
    }

    // MARK: - Stuck Detection

    func testStuckNarrative() {
        let stuckInfo = StuckDetector.StuckInfo(retryCount: 5, duration: 300, pattern: "compile error")
        let summary = SessionNarrative.summarize(
            state: .error,
            events: [],
            stats: makeStats(),
            taskStartedAt: nil,
            stuckInfo: stuckInfo
        )
        XCTAssert(summary.headline.contains("Stuck"), "Should say stuck: \(summary.headline)")
        XCTAssert(summary.headline.contains("compile error"), "Should include pattern: \(summary.headline)")
        XCTAssertTrue(summary.needsAttention)
    }
}
