import XCTest
@testable import Core

final class CompletionActionsTests: XCTestCase {

    private let testSessionId = UUID()

    private func makeEvent(_ kind: ActivityEvent.EventKind, ago: TimeInterval = 0) -> ActivityEvent {
        ActivityEvent(
            timestamp: Date().addingTimeInterval(-ago),
            sessionId: testSessionId,
            sessionName: "test",
            kind: kind
        )
    }

    private func makeContext(
        files: [String] = [],
        duration: TimeInterval = 120,
        hasTestCommand: Bool = false,
        cost: Double = 0,
        events: [ActivityEvent] = [],
        narrative: SessionNarrative.Summary? = nil,
        stuckInfo: StuckDetector.StuckInfo? = nil
    ) -> CompletionActions.CompletionContext {
        let stats = SessionStats()
        if cost > 0 { stats.recordCost(cost) }
        return CompletionActions.CompletionContext(
            filesChanged: files,
            taskDuration: duration,
            hasTestCommand: hasTestCommand,
            stats: stats,
            events: events,
            narrative: narrative,
            stuckInfo: stuckInfo
        )
    }

    // MARK: - Suggest Actions

    func testSuggestOpenDiff() {
        let ctx = makeContext(files: ["a.ts", "b.ts"])
        let actions = CompletionActions.suggest(context: ctx)
        XCTAssert(actions.contains(where: { $0.id == "open_diff" }))
    }

    func testSuggestNoActionsWhenEmpty() {
        let ctx = makeContext(files: [], duration: 10)
        let actions = CompletionActions.suggest(context: ctx)
        XCTAssertTrue(actions.isEmpty)
    }

    func testSuggestReviewAgentOnLongTask() {
        let ctx = makeContext(files: ["a.ts"], duration: 120)
        let actions = CompletionActions.suggest(context: ctx)
        XCTAssert(actions.contains(where: { $0.id == "start_review" }))
    }

    func testSuggestNoReviewOnShortTask() {
        let ctx = makeContext(files: ["a.ts"], duration: 30)
        let actions = CompletionActions.suggest(context: ctx)
        XCTAssertFalse(actions.contains(where: { $0.id == "start_review" }))
    }

    func testSuggestTestsWhenDetected() {
        let events = [
            makeEvent(.commandRun(command: "npm test"), ago: 60),
            makeEvent(.commandCompleted(command: "npm test", exitCode: 0, duration: 10), ago: 50),
        ]
        let ctx = makeContext(events: events)
        let actions = CompletionActions.suggest(context: ctx)
        XCTAssert(actions.contains(where: { $0.id == "run_tests" }))
    }

    func testSuggestRerunTestsWhenFailing() {
        let events = [
            makeEvent(.commandRun(command: "npm test"), ago: 60),
            makeEvent(.commandCompleted(command: "npm test", exitCode: 1, duration: 10), ago: 50),
        ]
        let ctx = makeContext(events: events)
        let actions = CompletionActions.suggest(context: ctx)
        let testAction = actions.first(where: { $0.id == "run_tests" })
        XCTAssertNotNil(testAction)
        XCTAssert(testAction!.label.contains("failing"), "Should say 'were failing': \(testAction!.label)")
    }

    // MARK: - Summary Line

    func testSummaryLineBasic() {
        let ctx = makeContext(files: ["a.ts", "b.ts"], duration: 300)
        let line = CompletionActions.summaryLine(context: ctx)
        XCTAssert(line.contains("2 files"), "Should mention files: \(line)")
        XCTAssert(line.contains("5m"), "Should mention duration: \(line)")
    }

    func testSummaryLineWithCost() {
        let ctx = makeContext(files: ["a.ts"], duration: 120, cost: 4.20)
        let line = CompletionActions.summaryLine(context: ctx)
        XCTAssert(line.contains("$4.20"), "Should mention cost: \(line)")
    }

    func testSummaryLineWithNarrative() {
        let narrative = SessionNarrative.Summary(
            headline: "Editing auth module",
            detail: nil,
            needsAttention: false
        )
        let ctx = makeContext(files: ["auth.ts"], duration: 60, narrative: narrative)
        let line = CompletionActions.summaryLine(context: ctx)
        XCTAssert(line.contains("Editing auth module"), "Should include narrative: \(line)")
    }

    func testSummaryLineWithTestsPassing() {
        let events = [
            makeEvent(.commandCompleted(command: "npm test", exitCode: 0, duration: 10), ago: 5),
        ]
        let ctx = makeContext(files: ["a.ts"], duration: 60, events: events)
        let line = CompletionActions.summaryLine(context: ctx)
        XCTAssert(line.contains("tests passing"), "Should mention test result: \(line)")
    }

    func testSummaryLineWithTestsFailing() {
        let events = [
            makeEvent(.commandCompleted(command: "swift test", exitCode: 1, duration: 10), ago: 5),
        ]
        let ctx = makeContext(files: ["a.ts"], duration: 60, events: events)
        let line = CompletionActions.summaryLine(context: ctx)
        XCTAssert(line.contains("tests failing"), "Should mention failing: \(line)")
    }

    // MARK: - Legacy API

    func testLegacyAPIStillWorks() {
        let actions = CompletionActions.suggest(
            filesChanged: ["a.ts"],
            taskDuration: 120,
            hasTestCommand: true
        )
        XCTAssert(actions.contains(where: { $0.id == "open_diff" }))
        XCTAssert(actions.contains(where: { $0.id == "run_tests" }))
        XCTAssert(actions.contains(where: { $0.id == "start_review" }))
    }
}
