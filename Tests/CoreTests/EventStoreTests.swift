import XCTest
@testable import Core

final class EventStoreTests: XCTestCase {

    func testRecordAndLoadSession() throws {
        let store = try EventStore()
        let sessionId = UUID()

        try store.recordSessionStart(
            sessionId: sessionId,
            projectId: "proj-1",
            projectPath: "/Users/test/project",
            name: "claude-1",
            agentType: "claude"
        )

        let sessions = try store.loadSessionHistory()
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].id, sessionId.uuidString)
        XCTAssertEqual(sessions[0].name, "claude-1")
        XCTAssertEqual(sessions[0].agentType, "claude")
        XCTAssertEqual(sessions[0].projectPath, "/Users/test/project")
        XCTAssertNil(sessions[0].endedAt)
    }

    func testRecordSessionEnd() throws {
        let store = try EventStore()
        let sessionId = UUID()

        try store.recordSessionStart(
            sessionId: sessionId, projectId: "proj-1",
            projectPath: nil, name: "test", agentType: nil
        )

        let stats = SessionStatsSnapshot(
            totalCost: 4.20, totalTasks: 3, totalErrors: 1,
            totalFilesChanged: 15, totalCommands: 8,
            totalSubagents: 2, totalIdleTime: 120
        )
        try store.recordSessionEnd(sessionId: sessionId, stats: stats)

        let sessions = try store.loadSessionHistory()
        XCTAssertEqual(sessions.count, 1)
        XCTAssertNotNil(sessions[0].endedAt)
        XCTAssertEqual(sessions[0].totalCost, 4.20, accuracy: 0.01)
        XCTAssertEqual(sessions[0].totalTasks, 3)
        XCTAssertEqual(sessions[0].totalErrors, 1)
        XCTAssertEqual(sessions[0].totalFilesChanged, 15)
    }

    func testPersistAndLoadEvents() throws {
        let store = try EventStore()
        let sessionId = UUID()

        try store.recordSessionStart(
            sessionId: sessionId, projectId: "proj-1",
            projectPath: nil, name: "test", agentType: nil
        )

        let events: [ActivityEvent] = [
            ActivityEvent(
                timestamp: Date(),
                sessionId: sessionId,
                sessionName: "test",
                kind: .fileWrite(path: "src/main.swift", added: 10, removed: 3)
            ),
            ActivityEvent(
                timestamp: Date(),
                sessionId: sessionId,
                sessionName: "test",
                kind: .commandRun(command: "swift build")
            ),
            ActivityEvent(
                timestamp: Date(),
                sessionId: sessionId,
                sessionName: "test",
                kind: .error(message: "Build failed: missing import")
            ),
        ]

        try store.persistEvents(events)

        let loaded = try store.loadEvents(sessionId: sessionId)
        XCTAssertEqual(loaded.count, 3)
        // Loaded in DESC order
        XCTAssertEqual(loaded[0].kind, "error")
        XCTAssertEqual(loaded[1].kind, "commandRun")
        XCTAssertEqual(loaded[2].kind, "fileWrite")
    }

    func testCountEvents() throws {
        let store = try EventStore()
        let sessionId = UUID()

        try store.recordSessionStart(
            sessionId: sessionId, projectId: "proj-1",
            projectPath: nil, name: "test", agentType: nil
        )

        let events: [ActivityEvent] = [
            ActivityEvent(timestamp: Date(), sessionId: sessionId, sessionName: "test",
                          kind: .error(message: "err1")),
            ActivityEvent(timestamp: Date(), sessionId: sessionId, sessionName: "test",
                          kind: .error(message: "err2")),
            ActivityEvent(timestamp: Date(), sessionId: sessionId, sessionName: "test",
                          kind: .fileWrite(path: "a.swift", added: nil, removed: nil)),
        ]
        try store.persistEvents(events)

        let total = try store.countEvents(sessionId: sessionId)
        XCTAssertEqual(total, 3)

        let errors = try store.countEvents(sessionId: sessionId, kind: "error")
        XCTAssertEqual(errors, 2)
    }

    func testLoadEventsFilterByKind() throws {
        let store = try EventStore()
        let sessionId = UUID()

        try store.recordSessionStart(
            sessionId: sessionId, projectId: "proj-1",
            projectPath: nil, name: "test", agentType: nil
        )

        let events: [ActivityEvent] = [
            ActivityEvent(timestamp: Date(), sessionId: sessionId, sessionName: "test",
                          kind: .taskStarted),
            ActivityEvent(timestamp: Date(), sessionId: sessionId, sessionName: "test",
                          kind: .fileWrite(path: "a.swift", added: 5, removed: 0)),
            ActivityEvent(timestamp: Date(), sessionId: sessionId, sessionName: "test",
                          kind: .taskCompleted(duration: 60)),
        ]
        try store.persistEvents(events)

        let writes = try store.loadEvents(sessionId: sessionId, kind: "fileWrite")
        XCTAssertEqual(writes.count, 1)
        XCTAssertEqual(writes[0].kind, "fileWrite")
    }

    func testTaskRecords() throws {
        let store = try EventStore()
        let sessionId = UUID()

        try store.recordSessionStart(
            sessionId: sessionId, projectId: "proj-1",
            projectPath: "/test", name: "test", agentType: "claude"
        )

        let taskId = try store.recordTaskStart(sessionId: sessionId)
        XCTAssertGreaterThan(taskId, 0)

        try store.recordTaskEnd(
            taskId: taskId, duration: 120, cost: 2.50,
            filesChanged: 5, commandsRun: 3, errorCount: 1,
            classification: "bugfix",
            files: ["src/a.swift", "src/b.swift"]
        )

        let tasks = try store.loadTaskRecords(sessionId: sessionId)
        XCTAssertEqual(tasks.count, 1)
        XCTAssertEqual(tasks[0].duration, 120)
        XCTAssertEqual(tasks[0].cost, 2.50)
        XCTAssertEqual(tasks[0].classification, "bugfix")
        XCTAssertEqual(tasks[0].files, ["src/a.swift", "src/b.swift"])
    }

    func testCostHistory() throws {
        let store = try EventStore()
        let sessionId = UUID()

        try store.recordSessionStart(
            sessionId: sessionId, projectId: "proj-1",
            projectPath: nil, name: "test", agentType: nil
        )

        try store.recordCost(sessionId: sessionId, cumulativeCost: 0.50)
        try store.recordCost(sessionId: sessionId, cumulativeCost: 1.20)
        try store.recordCost(sessionId: sessionId, cumulativeCost: 2.10)

        let history = try store.loadCostHistory(sessionId: sessionId)
        XCTAssertEqual(history.count, 3)
        XCTAssertEqual(history[0].1, 0.50, accuracy: 0.01)
        XCTAssertEqual(history[2].1, 2.10, accuracy: 0.01)
    }

    func testCostByProject() throws {
        let store = try EventStore()
        let session1 = UUID()
        let session2 = UUID()

        try store.recordSessionStart(
            sessionId: session1, projectId: "proj-1",
            projectPath: "/project-a", name: "s1", agentType: nil
        )
        try store.recordSessionStart(
            sessionId: session2, projectId: "proj-2",
            projectPath: "/project-b", name: "s2", agentType: nil
        )

        try store.recordSessionEnd(
            sessionId: session1,
            stats: SessionStatsSnapshot(totalCost: 5.0, totalTasks: 2, totalErrors: 0,
                                        totalFilesChanged: 10, totalCommands: 5,
                                        totalSubagents: 0, totalIdleTime: 0)
        )
        try store.recordSessionEnd(
            sessionId: session2,
            stats: SessionStatsSnapshot(totalCost: 3.0, totalTasks: 1, totalErrors: 0,
                                        totalFilesChanged: 5, totalCommands: 2,
                                        totalSubagents: 0, totalIdleTime: 0)
        )

        let costs = try store.costByProject()
        XCTAssertEqual(costs.count, 2)
        XCTAssertEqual(costs[0].projectPath, "/project-a") // highest cost first
        XCTAssertEqual(costs[0].cost, 5.0, accuracy: 0.01)
    }

    func testCleanupEvents() throws {
        let store = try EventStore()
        let sessionId = UUID()

        try store.recordSessionStart(
            sessionId: sessionId, projectId: "proj-1",
            projectPath: nil, name: "test", agentType: nil
        )

        // Insert an event with a timestamp 100 days ago
        let oldTimestamp = Date().addingTimeInterval(-100 * 86400)
        let recentTimestamp = Date()

        let events: [ActivityEvent] = [
            ActivityEvent(timestamp: oldTimestamp, sessionId: sessionId, sessionName: "test",
                          kind: .taskStarted),
            ActivityEvent(timestamp: recentTimestamp, sessionId: sessionId, sessionName: "test",
                          kind: .taskCompleted(duration: 60)),
        ]
        try store.persistEvents(events)

        try store.cleanupEvents(olderThanDays: 90)

        let remaining = try store.loadEvents(sessionId: sessionId)
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining[0].kind, "taskCompleted")
    }

    func testLoadSessionHistoryFilterByProject() throws {
        let store = try EventStore()

        try store.recordSessionStart(
            sessionId: UUID(), projectId: "p1",
            projectPath: "/project-a", name: "s1", agentType: nil
        )
        try store.recordSessionStart(
            sessionId: UUID(), projectId: "p2",
            projectPath: "/project-b", name: "s2", agentType: nil
        )

        let filtered = try store.loadSessionHistory(projectPath: "/project-a")
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered[0].name, "s1")
    }

    func testUpdateSessionModel() throws {
        let store = try EventStore()
        let sessionId = UUID()

        try store.recordSessionStart(
            sessionId: sessionId, projectId: "p1",
            projectPath: nil, name: "test", agentType: "claude"
        )

        try store.updateSessionModel(sessionId: sessionId, model: "claude-opus-4-6")

        let sessions = try store.loadSessionHistory()
        XCTAssertEqual(sessions[0].model, "claude-opus-4-6")
    }
}
